"""Firefly III enricher: PayPal phase.

For each Firefly journal whose destination is "PAYPAL PAYMENT", look up the
matching PayPal receipt email in Gmail (via the `gws` CLI) and write merchant
metadata into the journal's `notes` field as YAML frontmatter under a single
top-level `enricher:` key. Idempotent: any pre-existing `enricher:` key short-
circuits the journal.
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
import requests
import yaml

ENRICHER_VERSION = 1

# Subject patterns from PayPal:
#   "Dott (emTransit BV): £2.75 GBP"
#   "Receipt for your payment to <Merchant>"
SUBJECT_AMOUNT_RE = re.compile(r"^(?P<merchant>.+?):\s*£\s*(?P<amount>[\d,]+\.\d{2})\s*GBP\s*$")
SUBJECT_RECEIPT_RE = re.compile(r"^Receipt for your payment to\s+(?P<merchant>.+?)\s*$")
# Body fragment: "transaction ID is 8XK12345AB678901C" or "Transaction ID: ..."
BODY_TX_ID_RE = re.compile(r"[Tt]ransaction\s*ID\s*[:\s]+\s*([A-Z0-9]{12,20})")
# Body fallback patterns. PayPal puts the recipient name into the body in
# different ways depending on the email template. We try a few.
#   "You sent £21.00 GBP to John Smith"
#   "You paid $14.40 USD to Liberated Syndicatio..."
#   "... sent \u20ac21 ... to Katharina Heyn Transaction details ..." (HTML stripped)
BODY_SENT_TO_RE = re.compile(r"You\s+(?:sent|paid)\s+[\u00a3$\u20ac][\d,]+(?:\.\d{2})?\s+(?:GBP|USD|EUR)\s+to\s+(.+?)(?:\s*\.|\n|<|$)")
BODY_TO_RECIPIENT_RE = re.compile(r"(?:sent|paid)\s+[\u00a3$\u20ac][\d.,]+(?:\s*[A-Z]{3})?\s+to\s+(.+?)\s+Transaction\b")


def log() -> logging.Logger:
    return logging.getLogger("firefly-enricher")


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

    def search_paypal_journals(self) -> list[dict]:
        """Return all transactions where destination = PAYPAL PAYMENT, type = withdrawal."""
        out: list[dict] = []
        page = 1
        # Search syntax: type:withdrawal destination_account_is:"PAYPAL PAYMENT"
        while True:
            r = requests.get(
                f"{self.base_url}/api/v1/search/transactions",
                headers=self._headers(),
                params={
                    "query": 'type:withdrawal destination_account_is:"PAYPAL PAYMENT"',
                    "page": page,
                    "limit": 100,
                },
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
        """PUT /api/v1/transactions/{group_id} updating one inner journal's notes."""
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


def gws(args: list[str], creds_file: str, gws_bin: str) -> dict:
    """Invoke the gws CLI and return parsed JSON."""
    env = os.environ.copy()
    env["GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE"] = creds_file
    proc = subprocess.run(
        [gws_bin, *args],
        env=env,
        check=True,
        capture_output=True,
        text=True,
    )
    # gws prints a "Using keyring backend: keyring" line on stderr; stdout is pure JSON
    return json.loads(proc.stdout)


def gmail_search_paypal(amount: str, after_iso: str, before_iso: str, *, creds_file: str, gws_bin: str) -> list[str]:
    """Return Gmail message IDs matching from PayPal + amount + date window."""
    q = f'(from:service@paypal.co.uk OR from:service@paypal.com) "£{amount}" after:{after_iso} before:{before_iso}'
    params = {"userId": "me", "q": q, "maxResults": 20}
    resp = gws(
        ["gmail", "users", "messages", "list", "--params", json.dumps(params)],
        creds_file=creds_file,
        gws_bin=gws_bin,
    )
    return [m["id"] for m in resp.get("messages", [])]


def gmail_get_message(msg_id: str, *, creds_file: str, gws_bin: str) -> dict:
    """Fetch full Gmail message (with body)."""
    params = {"userId": "me", "id": msg_id, "format": "full"}
    return gws(
        ["gmail", "users", "messages", "get", "--params", json.dumps(params)],
        creds_file=creds_file,
        gws_bin=gws_bin,
    )


def decode_body(payload: dict) -> str:
    """Walk the payload and concatenate any text/plain or text/html bodies, decoded."""
    chunks: list[str] = []

    def walk(part: dict) -> None:
        body = part.get("body", {})
        data = body.get("data")
        if data:
            try:
                raw = urlsafe_b64decode(data + "==")
                chunks.append(raw.decode("utf-8", errors="replace"))
            except Exception:
                pass
        for sub in part.get("parts", []) or []:
            walk(sub)

    walk(payload)
    return "\n".join(chunks)


def parse_subject(subject: str) -> tuple[str | None, bool]:
    """Return (merchant, truncated?) parsed from a PayPal subject line.

    truncated=True means we should look at the body for the full merchant name.
    """
    m = SUBJECT_AMOUNT_RE.match(subject)
    if m:
        return m.group("merchant").strip(), False
    m = SUBJECT_RECEIPT_RE.match(subject)
    if m:
        merchant = m.group("merchant").strip()
        return merchant, merchant.endswith("...")
    return None, False


def extract_email_metadata(msg: dict) -> dict:
    """Return {merchant, transaction_id, raw_subject, email_date}."""
    headers = {h["name"]: h["value"] for h in msg.get("payload", {}).get("headers", [])}
    subject = headers.get("Subject", "")
    date = headers.get("Date", "")
    merchant, truncated = parse_subject(subject)
    body = decode_body(msg.get("payload", {}))

    if not merchant:
        # Strip HTML tags before searching (the second pattern needs collapsed text)
        text = re.sub(r"<[^>]+>", " ", body)
        text = re.sub(r"\s+", " ", text)
        m = BODY_TO_RECIPIENT_RE.search(text)
        if not m:
            m = BODY_SENT_TO_RE.search(body)
        if m:
            merchant = m.group(1).strip().rstrip(".")
            truncated = merchant.endswith("...")

    tx_id_match = BODY_TX_ID_RE.search(body)
    tx_id = tx_id_match.group(1) if tx_id_match else None

    return {
        "merchant": merchant,
        "merchant_truncated": truncated,
        "transaction_id": tx_id,
        "raw_subject": subject,
        "email_date": date,
    }


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
    # find closing ---
    for i in range(1, len(lines)):
        if lines[i].strip() == FRONTMATTER_DELIM:
            try:
                fm = yaml.safe_load("\n".join(lines[1:i])) or {}
            except yaml.YAMLError:
                # malformed; treat whole thing as body
                return {}, notes
            body = "\n".join(lines[i + 1 :])
            # strip a single leading blank line in the body for cleanliness
            if body.startswith("\n"):
                body = body[1:]
            return fm, body
    # unclosed frontmatter; treat as body
    return {}, notes


def merge_notes(notes: str | None, enricher_block: dict) -> str:
    """Merge our `enricher:` key into existing frontmatter, preserving body."""
    fm, body = split_notes(notes)
    fm["enricher"] = enricher_block
    fm_yaml = yaml.safe_dump(fm, sort_keys=False, allow_unicode=True).rstrip() + "\n"
    out = f"{FRONTMATTER_DELIM}\n{fm_yaml}{FRONTMATTER_DELIM}\n"
    if body:
        out += "\n" + body if not body.startswith("\n") else body
    return out


def is_already_enriched(notes: str | None) -> bool:
    fm, _ = split_notes(notes)
    return "enricher" in fm


# --- bank date helpers ---

def parse_bank_date(date_iso: str) -> dt.date:
    # Firefly returns "2026-04-28T22:00:00+00:00" or similar
    return dt.datetime.fromisoformat(date_iso.replace("Z", "+00:00")).date()


def gmail_date_window(bank_date: dt.date, *, lookback_days: int = 10, lookahead_days: int = 1) -> tuple[str, str]:
    """Return (after, before) in YYYY/MM/DD strings.

    Default: search from `lookback_days` before bank_date until `lookahead_days` after.
    """
    after = bank_date - dt.timedelta(days=lookback_days)
    before = bank_date + dt.timedelta(days=lookahead_days)
    return after.strftime("%Y/%m/%d"), before.strftime("%Y/%m/%d")


# --- main ---

def pick_best_candidate(candidates: list[dict], bank_date: dt.date) -> tuple[dict | None, str]:
    """Return (best_candidate, reason).

    reason is one of: matched, ambiguous_across_merchants, no_candidates.
    """
    if not candidates:
        return None, "no_candidates"
    merchants = {c.get("merchant") for c in candidates if c.get("merchant")}
    if len(merchants) > 1:
        return None, "ambiguous_across_merchants"
    # parse email_date and pick the latest one before/at the bank_date (closest in time)

    def email_d(c: dict) -> dt.datetime:
        try:
            return dt.datetime.strptime(c["email_date"], "%a, %d %b %Y %H:%M:%S %z")
        except (ValueError, KeyError):
            return dt.datetime.min.replace(tzinfo=dt.timezone.utc)

    candidates.sort(key=email_d, reverse=True)
    return candidates[0], "matched"


def process_journal(
    j: dict,
    *,
    firefly: FireflyClient,
    creds_file: str,
    gws_bin: str,
    dry_run: bool,
) -> str:
    """Return a status string describing what happened to this journal."""
    attrs = j["attributes"]
    group_id = int(j["id"])
    inner = attrs["transactions"][0]
    journal_id = int(inner["transaction_journal_id"])
    notes = inner.get("notes") or ""
    if is_already_enriched(notes):
        return f"skip:already_enriched id={journal_id}"

    amount = inner["amount"]  # string like "2.75"
    # normalize the amount to 2dp (strip trailing zeros if any, but PayPal uses "2.75" form)
    # ensure 2dp:
    amt_decimal = f"{float(amount):.2f}"
    bank_date = parse_bank_date(inner["date"])
    after, before = gmail_date_window(bank_date)

    log().info(
        "journal=%d date=%s amount=£%s window=%s..%s",
        journal_id, bank_date, amt_decimal, after, before,
    )

    msg_ids = gmail_search_paypal(amt_decimal, after, before, creds_file=creds_file, gws_bin=gws_bin)
    candidates: list[dict] = []
    for mid in msg_ids:
        try:
            msg = gmail_get_message(mid, creds_file=creds_file, gws_bin=gws_bin)
        except subprocess.CalledProcessError:
            continue
        meta = extract_email_metadata(msg)
        meta["gmail_id"] = mid
        candidates.append(meta)

    pick, reason = pick_best_candidate(candidates, bank_date)

    block: dict = {
        "version": ENRICHER_VERSION,
        "fetched_at": dt.datetime.now(tz=dt.timezone.utc).isoformat(timespec="seconds"),
        "paypal": {"matched": pick is not None},
    }
    if pick:
        seller_block = {
            "gmail_id": pick["gmail_id"],
            "email_date": pick["email_date"],
            "seller": pick["merchant"],
            "transaction_id": pick.get("transaction_id"),
            "raw_subject": pick["raw_subject"],
        }
        if pick.get("merchant_truncated"):
            seller_block["seller_truncated"] = True
        block["paypal"].update(seller_block)
    else:
        block["paypal"]["reason"] = reason
        if reason == "ambiguous_across_merchants":
            block["paypal"]["candidates"] = [
                {
                    "gmail_id": c["gmail_id"],
                    "seller": c["merchant"],
                    "email_date": c["email_date"],
                    "raw_subject": c["raw_subject"],
                }
                for c in candidates
            ]

    new_notes = merge_notes(notes, block)
    if dry_run:
        return f"dryrun:{reason} id={journal_id} would_write\n{new_notes}\n---"
    firefly.update_journal_notes(group_id, journal_id, new_notes)
    return f"ok:{reason} id={journal_id} seller={(pick or {}).get('merchant')!r}"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--firefly-url", default=os.environ.get("FIREFLY_URL", "http://firefly.nexus.hosts.10.0.0.2.nip.io"))
    p.add_argument("--firefly-token-file", default=os.environ.get("FIREFLY_TOKEN_FILE", "/var/lib/firefly-importer/access-token.txt"))
    p.add_argument("--gws-creds-file", default=os.environ.get("GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE", "/var/lib/scout/gws-credentials.json"))
    p.add_argument("--gws-bin", default=os.environ.get("GWS_BIN", "gws"))
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--limit", type=int, default=None, help="process at most N journals (handy for testing)")
    p.add_argument("-v", "--verbose", action="store_true")
    args = p.parse_args(argv)

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO, format="%(levelname)s %(message)s")

    with open(args.firefly_token_file) as f:
        token = f.read().strip()

    firefly = FireflyClient(base_url=args.firefly_url.rstrip("/"), token=token)

    log().info("fetching PayPal journals from Firefly")
    journals = firefly.search_paypal_journals()
    log().info("found %d journals", len(journals))

    todo = [j for j in journals if not is_already_enriched(j["attributes"]["transactions"][0].get("notes") or "")]
    log().info("%d not yet enriched", len(todo))
    if args.limit is not None:
        todo = todo[: args.limit]
        log().info("limiting to %d", len(todo))

    for j in todo:
        try:
            result = process_journal(j, firefly=firefly, creds_file=args.gws_creds_file, gws_bin=args.gws_bin, dry_run=args.dry_run)
            print(result, file=sys.stderr)
        except Exception as e:
            log().exception("error on journal %s: %s", j.get("id"), e)
        time.sleep(0.2)  # gentle on Gmail

    return 0


if __name__ == "__main__":
    sys.exit(main())
