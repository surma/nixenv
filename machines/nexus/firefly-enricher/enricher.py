"""Firefly III enricher.

For each Firefly III withdrawal journal whose destination is a known opaque
merchant (PayPal, Amazon...), look up the matching receipt email in Gmail
(via the `gws` CLI) and write the resolved details into the journal's `notes`
field as YAML frontmatter under a single top-level `enricher:` key, namespaced
per source. Idempotent: any pre-existing `enricher.<source>` sub-key short-
circuits the journal for that source.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import logging
import os
import re
import subprocess
import sys
import time
from base64 import urlsafe_b64decode
from dataclasses import dataclass
from typing import Callable
import requests
import yaml

ENRICHER_VERSION = 1


def log() -> logging.Logger:
    return logging.getLogger("firefly-enricher")


# --- Firefly III API ---


@dataclass
class FireflyClient:
    base_url: str
    token: str

    def _headers(self) -> dict[str, str]:
        return {
            "Authorization": f"Bearer {self.token}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        }

    def search_transactions(self, query: str) -> list[dict]:
        out: list[dict] = []
        page = 1
        while True:
            r = requests.get(
                f"{self.base_url}/api/v1/search/transactions",
                headers=self._headers(),
                params={"query": query, "page": page, "limit": 100},
                timeout=30,
            )
            r.raise_for_status()
            data = r.json()
            out.extend(data.get("data", []))
            pagination = data.get("meta", {}).get("pagination", {})
            if page >= pagination.get("total_pages", 1):
                break
            page += 1
        return out

    def update_journal_notes(self, group_id: int, journal_id: int, notes: str) -> None:
        r = requests.put(
            f"{self.base_url}/api/v1/transactions/{group_id}",
            headers=self._headers(),
            json={
                "apply_rules": False,
                "transactions": [
                    {"transaction_journal_id": journal_id, "notes": notes},
                ],
            },
            timeout=30,
        )
        r.raise_for_status()


# --- Gmail API via gws ---


@dataclass
class GmailContext:
    creds_file: str
    gws_bin: str


def gws(args: list[str], ctx: GmailContext) -> dict:
    """Invoke the gws CLI and return parsed JSON."""
    env = os.environ.copy()
    env["GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE"] = ctx.creds_file
    proc = subprocess.run(
        [ctx.gws_bin, *args],
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )
    # gws prints "Using keyring backend: keyring" to stderr; stdout is pure JSON
    return json.loads(proc.stdout)


def gmail_list(query: str, ctx: GmailContext, max_results: int = 20) -> list[str]:
    params = {"userId": "me", "q": query, "maxResults": max_results}
    resp = gws(
        ["gmail", "users", "messages", "list", "--params", json.dumps(params)], ctx
    )
    return [m["id"] for m in resp.get("messages", [])]


def gmail_get(msg_id: str, ctx: GmailContext) -> dict:
    params = {"userId": "me", "id": msg_id, "format": "full"}
    return gws(
        ["gmail", "users", "messages", "get", "--params", json.dumps(params)], ctx
    )


def decode_body(payload: dict, prefer_mime: str | None = None) -> str:
    """Walk the payload and return decoded body content.

    If `prefer_mime` is set (e.g. 'text/plain'), return only that part if
    present; otherwise concatenate all text/* parts.
    """
    text_plain: list[str] = []
    text_html: list[str] = []

    def walk(part: dict) -> None:
        body = part.get("body", {})
        data = body.get("data")
        if data:
            try:
                raw = urlsafe_b64decode(data + "==").decode("utf-8", errors="replace")
                mt = part.get("mimeType", "")
                if mt == "text/plain":
                    text_plain.append(raw)
                elif mt == "text/html":
                    text_html.append(raw)
                else:
                    # treat unknown leaf as plain
                    text_plain.append(raw)
            except Exception:
                pass
        for sub in part.get("parts", []) or []:
            walk(sub)

    walk(payload)
    if prefer_mime == "text/plain" and text_plain:
        return "\n".join(text_plain)
    return "\n".join(text_plain + text_html)


def email_headers(msg: dict) -> dict[str, str]:
    return {h["name"]: h["value"] for h in msg.get("payload", {}).get("headers", [])}


# --- frontmatter handling ---

FRONTMATTER_DELIM = "---"


def split_notes(notes: str | None) -> tuple[dict, str]:
    """Return (frontmatter_dict, body) from `notes`.

    If no leading frontmatter, frontmatter_dict={} and body=notes verbatim.
    """
    if not notes:
        return {}, ""
    lines = notes.splitlines()
    if not lines or lines[0].strip() != FRONTMATTER_DELIM:
        return {}, notes
    for i in range(1, len(lines)):
        if lines[i].strip() == FRONTMATTER_DELIM:
            try:
                fm = yaml.safe_load("\n".join(lines[1:i])) or {}
            except yaml.YAMLError:
                return {}, notes
            body = "\n".join(lines[i + 1:])
            if body.startswith("\n"):
                body = body[1:]
            return fm, body
    return {}, notes


def merge_notes(notes: str | None, source_name: str, source_block: dict) -> str:
    """Merge `enricher.<source_name>` into existing frontmatter, preserving body."""
    fm, body = split_notes(notes)
    enricher = fm.get("enricher") or {}
    enricher["version"] = ENRICHER_VERSION
    enricher["fetched_at"] = dt.datetime.now(tz=dt.timezone.utc).isoformat(timespec="seconds")
    enricher[source_name] = source_block
    fm["enricher"] = enricher
    fm_yaml = yaml.safe_dump(fm, sort_keys=False, allow_unicode=True).rstrip() + "\n"
    out = f"{FRONTMATTER_DELIM}\n{fm_yaml}{FRONTMATTER_DELIM}\n"
    if body:
        out += "\n" + body if not body.startswith("\n") else body
    return out


def is_already_enriched_by(notes: str | None, source_name: str) -> bool:
    fm, _ = split_notes(notes)
    enricher = fm.get("enricher") or {}
    return source_name in enricher


# --- bank date helpers ---


def parse_bank_date(date_iso: str) -> dt.date:
    return dt.datetime.fromisoformat(date_iso.replace("Z", "+00:00")).date()


def gmail_date_window(bank_date: dt.date, *, lookback_days: int, lookahead_days: int) -> tuple[str, str]:
    after = bank_date - dt.timedelta(days=lookback_days)
    before = bank_date + dt.timedelta(days=lookahead_days)
    return after.strftime("%Y/%m/%d"), before.strftime("%Y/%m/%d")


def parse_email_datetime(date_str: str) -> dt.datetime:
    """Parse an RFC 2822 email Date header. Returns dt.datetime.min on failure."""
    for fmt in ("%a, %d %b %Y %H:%M:%S %z", "%d %b %Y %H:%M:%S %z"):
        try:
            return dt.datetime.strptime(date_str, fmt)
        except (ValueError, TypeError):
            continue
    return dt.datetime.min.replace(tzinfo=dt.timezone.utc)


# --- PayPal source ---

# "Dott (emTransit BV): £2.75 GBP"
PAYPAL_SUBJECT_AMOUNT_RE = re.compile(r"^(?P<merchant>.+?):\s*£\s*(?P<amount>[\d,]+\.\d{2})\s*GBP\s*$")
# "Receipt for your payment to <Merchant>"
PAYPAL_SUBJECT_RECEIPT_RE = re.compile(r"^Receipt for your payment to\s+(?P<merchant>.+?)\s*$")
# Body: "transaction ID is 8XK12345AB678901C" or "Transaction ID: ..."
PAYPAL_BODY_TX_ID_RE = re.compile(r"[Tt]ransaction\s*ID\s*[:\s]+\s*([A-Z0-9]{12,20})")
# Body fallbacks for merchant when subject doesn't carry it:
#   "You sent £21.00 GBP to John Smith"
#   "You paid $14.40 USD to Liberated Syndicatio..."
PAYPAL_BODY_SENT_TO_RE = re.compile(
    r"You\s+(?:sent|paid)\s+[\u00a3$\u20ac][\d,]+(?:\.\d{2})?\s+(?:GBP|USD|EUR)\s+to\s+(.+?)(?:\s*\.|\n|<|$)"
)
# HTML-stripped: "...sent €21 ... to Katharina Heyn Transaction details ..."
PAYPAL_BODY_TO_RECIPIENT_RE = re.compile(
    r"(?:sent|paid)\s+[\u00a3$\u20ac][\d.,]+(?:\s*[A-Z]{3})?\s+to\s+(.+?)\s+Transaction\b"
)


def paypal_parse_subject(subject: str) -> tuple[str | None, bool]:
    """Return (merchant, truncated?). truncated means 'subject ends with ...'."""
    m = PAYPAL_SUBJECT_AMOUNT_RE.match(subject)
    if m:
        return m.group("merchant").strip(), False
    m = PAYPAL_SUBJECT_RECEIPT_RE.match(subject)
    if m:
        merchant = m.group("merchant").strip()
        return merchant, merchant.endswith("...")
    return None, False


def paypal_extract(msg: dict, gmail_id: str) -> dict:
    headers = email_headers(msg)
    subject = headers.get("Subject", "")
    date = headers.get("Date", "")
    merchant, truncated = paypal_parse_subject(subject)
    body = decode_body(msg.get("payload", {}))

    if not merchant:
        text = re.sub(r"<[^>]+>", " ", body)
        text = re.sub(r"\s+", " ", text)
        m = PAYPAL_BODY_TO_RECIPIENT_RE.search(text)
        if not m:
            m = PAYPAL_BODY_SENT_TO_RE.search(body)
        if m:
            merchant = m.group(1).strip().rstrip(".")
            truncated = merchant.endswith("...")

    tx_match = PAYPAL_BODY_TX_ID_RE.search(body)
    return {
        "gmail_id": gmail_id,
        "email_date": date,
        "merchant": merchant,
        "merchant_truncated": truncated,
        "transaction_id": tx_match.group(1) if tx_match else None,
        "raw_subject": subject,
    }


def paypal_resolve(journal: dict, gmail: GmailContext) -> dict:
    inner = journal["attributes"]["transactions"][0]
    amount = f"{float(inner['amount']):.2f}"
    bank_date = parse_bank_date(inner["date"])
    after, before = gmail_date_window(bank_date, lookback_days=10, lookahead_days=1)

    log().info(
        "[paypal] journal=%s date=%s amount=£%s window=%s..%s",
        inner["transaction_journal_id"], bank_date, amount, after, before,
    )

    q = (
        f'(from:service@paypal.co.uk OR from:service@paypal.com) '
        f'"£{amount}" after:{after} before:{before}'
    )
    msg_ids = gmail_list(q, gmail)
    candidates: list[dict] = []
    for mid in msg_ids:
        try:
            msg = gmail_get(mid, gmail)
        except subprocess.CalledProcessError:
            continue
        candidates.append(paypal_extract(msg, mid))

    if not candidates:
        return {"matched": False, "reason": "no_candidates"}

    merchants = {c.get("merchant") for c in candidates if c.get("merchant")}
    if len(merchants) > 1:
        return {
            "matched": False,
            "reason": "ambiguous_across_merchants",
            "candidates": [
                {
                    "gmail_id": c["gmail_id"],
                    "seller": c["merchant"],
                    "email_date": c["email_date"],
                    "raw_subject": c["raw_subject"],
                }
                for c in candidates
            ],
        }

    candidates.sort(key=lambda c: parse_email_datetime(c["email_date"]), reverse=True)
    pick = candidates[0]
    block = {
        "matched": True,
        "gmail_id": pick["gmail_id"],
        "email_date": pick["email_date"],
        "seller": pick["merchant"],
        "transaction_id": pick.get("transaction_id"),
        "raw_subject": pick["raw_subject"],
    }
    if pick.get("merchant_truncated"):
        block["seller_truncated"] = True
    return block


# --- Amazon source ---

# Order ID format: 203-7685657-3119503
AMAZON_ORDER_ID_RE = re.compile(r"\b(\d{3}-\d{7}-\d{7})\b")
# "Total\n  52.989999999999995 GBP" or "Total 52.99 GBP"
AMAZON_TOTAL_RE = re.compile(r"\bTotal\b\s*[\n ]+\s*([\d.]+)\s*GBP", re.IGNORECASE)
# Item line in text/plain Dispatched email (CRLF in the wild):
#   "* WANPTEK POWER Bench Power Supply Variable 0-30V..."
#   "  Quantity: 1"
#   "  52.99 GBP"
AMAZON_ITEM_BLOCK_RE = re.compile(
    r"\*\s+(?P<title>.+?)\r?\n"
    r"\s+Quantity:\s+(?P<qty>\d+)\r?\n"
    r"\s+(?P<amount>[\d.]+)\s*GBP",
    re.DOTALL,
)


def amazon_parse_dispatched(msg: dict) -> dict | None:
    """Parse a Dispatched email body. Returns {order_id, items, total} or None."""
    body = decode_body(msg.get("payload", {}), prefer_mime="text/plain")
    if not body:
        return None
    total_m = AMAZON_TOTAL_RE.search(body)
    if not total_m:
        return None
    try:
        total = round(float(total_m.group(1)), 2)
    except ValueError:
        return None
    order_m = AMAZON_ORDER_ID_RE.search(body)
    items: list[dict] = []
    for im in AMAZON_ITEM_BLOCK_RE.finditer(body):
        try:
            item_amount = round(float(im.group("amount")), 2)
        except ValueError:
            continue
        title = re.sub(r"\s+", " ", im.group("title")).strip()
        items.append(
            {
                "title": title,
                "quantity": int(im.group("qty")),
                "amount": item_amount,
            }
        )
    return {
        "order_id": order_m.group(1) if order_m else None,
        "total": total,
        "items": items,
    }


def amazon_resolve(journal: dict, gmail: GmailContext) -> dict:
    inner = journal["attributes"]["transactions"][0]
    dest = (inner.get("destination_name") or "").upper()
    bank_amount = round(float(inner["amount"]), 2)
    bank_date = parse_bank_date(inner["date"])

    # Prime Video / digital purchases ship via different emails ("Your
    # Amazon.co.uk video rental..."); not handled in this phase.
    if "AMZN DIGITAL" in dest or "AMAZON DIGITAL" in dest:
        return {"matched": False, "reason": "amazon_digital_unsupported"}

    # Amazon charges at shipment, so the Dispatched email lands within ~0-2
    # days of the bank charge. ±5 days gives us comfortable margin.
    after, before = gmail_date_window(bank_date, lookback_days=5, lookahead_days=2)

    log().info(
        "[amazon] journal=%s date=%s amount=£%.2f dest=%s window=%s..%s",
        inner["transaction_journal_id"], bank_date, bank_amount, dest, after, before,
    )

    # Search for Dispatched emails (which have per-shipment totals matching
    # the bank charge). Some retail orders use slightly different templates,
    # so we try Dispatched first and fall back to other shipment events.
    queries = [
        f"from:amazon.co.uk subject:Dispatched after:{after} before:{before}",
        f"from:amazon.co.uk (subject:Dispatched OR subject:shipped) after:{after} before:{before}",
    ]
    seen_ids: set[str] = set()
    parsed: list[tuple[str, dt.datetime, dict]] = []
    for q in queries:
        msg_ids = gmail_list(q, gmail, max_results=30)
        for mid in msg_ids:
            if mid in seen_ids:
                continue
            seen_ids.add(mid)
            try:
                msg = gmail_get(mid, gmail)
            except subprocess.CalledProcessError:
                continue
            extracted = amazon_parse_dispatched(msg)
            if extracted is None:
                continue
            if extracted["total"] != bank_amount:
                continue
            headers = email_headers(msg)
            edate = parse_email_datetime(headers.get("Date", ""))
            extracted["gmail_id"] = mid
            extracted["email_date"] = headers.get("Date", "")
            extracted["raw_subject"] = headers.get("Subject", "")
            parsed.append((mid, edate, extracted))
        if parsed:
            break  # first non-empty query wins

    if not parsed:
        return {"matched": False, "reason": "no_dispatched_email"}

    if len(parsed) > 1:
        # Pick the email closest in time to the bank charge date (typically same day).
        bank_dt = dt.datetime.combine(bank_date, dt.time(0, 0, tzinfo=dt.timezone.utc))
        parsed.sort(key=lambda t: abs((t[1] - bank_dt).total_seconds()))

    _, edate, info = parsed[0]
    block = {
        "matched": True,
        "gmail_id": info["gmail_id"],
        "email_date": info["email_date"],
        "raw_subject": info["raw_subject"],
        "order_id": info["order_id"],
        "total": info["total"],
        "items": info["items"],
    }
    if len(parsed) > 1:
        block["disambiguated_by"] = "closest_date"
        block["other_candidates"] = [
            {"gmail_id": mid, "raw_subject": ext["raw_subject"]}
            for mid, _, ext in parsed[1:]
        ]
    return block


# --- Source registry & main loop ---


@dataclass
class Source:
    name: str
    firefly_query: str
    resolve: Callable[[dict, GmailContext], dict]
    description: str = ""


SOURCES: list[Source] = [
    Source(
        name="paypal",
        firefly_query='type:withdrawal destination_account_is:"PAYPAL PAYMENT"',
        resolve=paypal_resolve,
        description="PayPal opaque charges resolved from Gmail receipts",
    ),
    # Amazon hits multiple Amex-side destination account names. The Firefly
    # search syntax doesn't OR multiple destination clauses cleanly, so we run
    # one search per name and dedupe.
    Source(
        name="amazon",
        firefly_query='type:withdrawal destination_account_starts:"AMAZON"',
        resolve=amazon_resolve,
        description="Amazon shipment-level itemisation from Gmail Dispatched emails",
    ),
    Source(
        name="amazon",
        firefly_query='type:withdrawal destination_account_starts:"UK AMZN"',
        resolve=amazon_resolve,
        description="Amazon digital (Prime Video etc.)",
    ),
]


def process_journal(j: dict, source: Source, firefly: FireflyClient, gmail: GmailContext, dry_run: bool) -> str:
    attrs = j["attributes"]
    group_id = int(j["id"])
    inner = attrs["transactions"][0]
    journal_id = int(inner["transaction_journal_id"])
    notes = inner.get("notes") or ""
    if is_already_enriched_by(notes, source.name):
        return f"skip:already_enriched source={source.name} id={journal_id}"

    block = source.resolve(j, gmail)
    new_notes = merge_notes(notes, source.name, block)
    matched = bool(block.get("matched"))
    summary_keys = ("seller", "order_id", "reason")
    summary = {k: block.get(k) for k in summary_keys if k in block}

    if dry_run:
        return f"dryrun:{source.name} id={journal_id} matched={matched} {summary} would_write\n{new_notes}\n---"
    firefly.update_journal_notes(group_id, journal_id, new_notes)
    return f"ok:{source.name} id={journal_id} matched={matched} {summary}"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--firefly-url", default=os.environ.get("FIREFLY_URL", "http://firefly.nexus.hosts.10.0.0.2.nip.io"))
    p.add_argument("--firefly-token-file", default=os.environ.get("FIREFLY_TOKEN_FILE", "/var/lib/firefly-importer/access-token.txt"))
    p.add_argument("--gws-creds-file", default=os.environ.get("GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE", "/var/lib/scout/gws-credentials.json"))
    p.add_argument("--gws-bin", default=os.environ.get("GWS_BIN", "gws"))
    p.add_argument("--source", action="append", help="restrict to source(s); default: all")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--limit", type=int, default=None, help="process at most N journals per source")
    p.add_argument("-v", "--verbose", action="store_true")
    args = p.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(message)s",
    )

    with open(args.firefly_token_file) as f:
        token = f.read().strip()
    firefly = FireflyClient(base_url=args.firefly_url.rstrip("/"), token=token)
    gmail = GmailContext(creds_file=args.gws_creds_file, gws_bin=args.gws_bin)

    sources = SOURCES
    if args.source:
        sources = [s for s in SOURCES if s.name in args.source]
        if not sources:
            log().error("no sources match --source %s", args.source)
            return 2

    seen_journals: set[int] = set()
    for source in sources:
        log().info(
            "fetching %s journals from Firefly (query=%r)",
            source.name, source.firefly_query,
        )
        journals = firefly.search_transactions(source.firefly_query)
        # dedupe across overlapping queries (e.g. two Amazon registrations)
        deduped: list[dict] = []
        for j in journals:
            jid = int(j["attributes"]["transactions"][0]["transaction_journal_id"])
            key = (source.name, jid)
            if key in seen_journals:
                continue
            seen_journals.add(key)
            deduped.append(j)
        log().info("found %d journals (%d new for this source)", len(journals), len(deduped))

        todo = [
            j for j in deduped
            if not is_already_enriched_by(
                j["attributes"]["transactions"][0].get("notes") or "", source.name
            )
        ]
        log().info("[%s] %d not yet enriched", source.name, len(todo))
        if args.limit is not None:
            todo = todo[: args.limit]
            log().info("[%s] limiting to %d", source.name, len(todo))

        for j in todo:
            try:
                result = process_journal(j, source, firefly, gmail, args.dry_run)
                print(result, file=sys.stderr)
            except Exception as e:
                log().exception(
                    "error on journal %s (source=%s): %s",
                    j.get("id"), source.name, e,
                )
            time.sleep(0.2)

    return 0


if __name__ == "__main__":
    sys.exit(main())
