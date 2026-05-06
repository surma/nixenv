"""Firefly III categoriser.

Subcommands:
  aggregate         - inventory merchants from Firefly (no LLM); writes JSON to stdout
  propose-taxonomy  - LLM call: propose {categories, tags} from the aggregate
  propose-mapping   - LLM call: propose {merchant: {category, tags}} given the aggregate + taxonomy
  run               - steady-state: categorise journals (uses curated merchant-map + LLM fallback)
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import logging
import os
import sys
import time
from collections import defaultdict
from dataclasses import dataclass
from typing import Any
import requests
import yaml


CATEGORISER_VERSION = 1

# Merchants whose category varies per transaction (Amazon orders mix Groceries
# / House / Tech / Books / etc.; PayPal F&F covers gifts, splits, donations).
# These never go in merchant-map.json; categoriser always routes them to the
# LLM with the enricher's per-transaction frontmatter as input.
POLYMORPHIC_PREFIXES = [
    "AMAZON",
    "UK AMZN",
    "PAYPAL PAYMENT",
]

FRONTMATTER_DELIM = "---"


def log() -> logging.Logger:
    return logging.getLogger("firefly-categoriser")


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

    def update_journal(self, group_id: int, journal_id: int, fields: dict) -> None:
        body = {
            "apply_rules": False,
            "transactions": [{"transaction_journal_id": journal_id, **fields}],
        }
        r = requests.put(
            f"{self.base_url}/api/v1/transactions/{group_id}",
            headers=self._headers(),
            json=body,
            timeout=30,
        )
        r.raise_for_status()


# --- frontmatter handling (matches enricher.py format) ---


def split_notes(notes: str | None) -> tuple[dict, str]:
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


def merge_categoriser(notes: str | None, block: dict) -> str:
    fm, body = split_notes(notes)
    enricher = fm.get("enricher") or {}
    enricher["version"] = enricher.get("version", 1)
    enricher["fetched_at"] = dt.datetime.now(tz=dt.timezone.utc).isoformat(timespec="seconds")
    enricher["categoriser"] = block
    fm["enricher"] = enricher
    fm_yaml = yaml.safe_dump(fm, sort_keys=False, allow_unicode=True).rstrip() + "\n"
    out = f"{FRONTMATTER_DELIM}\n{fm_yaml}{FRONTMATTER_DELIM}\n"
    if body:
        out += "\n" + body if not body.startswith("\n") else body
    return out


def has_categoriser_block(notes: str | None) -> bool:
    fm, _ = split_notes(notes)
    return "categoriser" in (fm.get("enricher") or {})


def existing_enricher_block(notes: str | None) -> dict:
    fm, _ = split_notes(notes)
    return fm.get("enricher") or {}


# --- aggregate subcommand ---


def is_polymorphic(merchant: str) -> bool:
    m = (merchant or "").upper()
    return any(m.startswith(p) for p in POLYMORPHIC_PREFIXES)


def aggregate_journals(firefly: FireflyClient) -> dict:
    """Return {merchants: {<name>: {...}}, polymorphic: [<name>...], totals: {...}}."""
    journals: list[dict] = []
    for q in ("type:withdrawal", "type:deposit"):
        log().info("fetching %r", q)
        journals.extend(firefly.search_transactions(q))

    log().info("aggregated %d journals (withdrawal + deposit)", len(journals))

    by_merchant: dict[str, dict] = defaultdict(
        lambda: {
            "count": 0,
            "total_gbp": 0.0,
            "type": None,            # withdrawal / deposit
            "asset_account": None,   # the user's account on the other side
            "samples": [],
        }
    )
    polymorphic_journals: list[dict] = []

    for j in journals:
        inner = j["attributes"]["transactions"][0]
        ttype = inner.get("type")
        if ttype == "withdrawal":
            merchant = inner.get("destination_name") or "(none)"
            asset = inner.get("source_name")
        elif ttype == "deposit":
            merchant = inner.get("source_name") or "(none)"
            asset = inner.get("destination_name")
        else:
            continue

        amount = float(inner.get("amount") or 0)
        desc = inner.get("description") or ""
        date = inner.get("date") or ""
        category = inner.get("category_name")

        if is_polymorphic(merchant):
            poly_entry: dict[str, Any] = {
                "journal_id": int(inner["transaction_journal_id"]),
                "merchant": merchant,
                "amount": amount,
                "type": ttype,
                "asset": asset,
                "description": desc,
                "date": date,
                "category_name": category,
            }
            # surface the enricher's resolved details so taxonomy proposal
            # sees categories that exist only via polymorphic merchants
            # (e.g. Books / Tech via Amazon line items, real seller via
            # PayPal). Stable merchants don't need this because merchant
            # string alone determines category.
            enricher = (split_notes(inner.get("notes"))[0] or {}).get("enricher") or {}
            amzn = enricher.get("amazon") or {}
            if amzn.get("matched"):
                poly_entry["amazon_items"] = [
                    {"title": it.get("title"), "amount": it.get("amount")}
                    for it in (amzn.get("items") or [])
                ]
                poly_entry["amazon_order_id"] = amzn.get("order_id")
            paypal = enricher.get("paypal") or {}
            if paypal.get("matched"):
                poly_entry["paypal_seller"] = paypal.get("seller")
            polymorphic_journals.append(poly_entry)
            continue

        m = by_merchant[merchant]
        m["count"] += 1
        m["total_gbp"] += amount
        m["type"] = ttype
        m["asset_account"] = asset
        if len(m["samples"]) < 3:
            m["samples"].append({
                "date": date,
                "amount": amount,
                "description": desc,
                "category_name": category,
            })

    # round totals
    for v in by_merchant.values():
        v["total_gbp"] = round(v["total_gbp"], 2)

    return {
        "generated_at": dt.datetime.now(tz=dt.timezone.utc).isoformat(timespec="seconds"),
        "merchants": dict(sorted(by_merchant.items(), key=lambda kv: -kv[1]["count"])),
        "polymorphic_journals": polymorphic_journals,
        "totals": {
            "stable_merchants": len(by_merchant),
            "stable_journals": sum(v["count"] for v in by_merchant.values()),
            "polymorphic_journals": len(polymorphic_journals),
            "polymorphic_prefixes": POLYMORPHIC_PREFIXES,
        },
    }


# --- LLM client (placeholder; filled in for propose-* subcommands) ---


@dataclass
class LLMClient:
    base_url: str
    api_key: str
    model: str

    def anthropic_messages_json(
        self,
        system: str,
        user: str,
        *,
        anthropic_model: str,
        max_tokens: int = 4096,
        thinking_effort: str | None = None,
    ) -> dict:
        """Anthropic native /apis/anthropic/v1/messages with optional thinking.

        Use for models the proxy gates behind the Messages API (Opus 4.6/4.7).
        Prompts the model to return raw JSON (no code fence); strips a fence
        anyway as a safety net.
        """
        sys_with_json = (
            system.rstrip()
            + "\n\nReturn your answer as a single JSON object. Output ONLY the"
            + " JSON. Do not wrap it in markdown or prose. Begin with `{` and"
            + " end with `}`."
        )
        body: dict[str, Any] = {
            "model": anthropic_model,
            "max_tokens": max_tokens,
            "system": sys_with_json,
            "messages": [{"role": "user", "content": user}],
        }
        if thinking_effort:
            # Opus 4.7+ uses adaptive thinking driven by output_config.effort,
            # not a fixed budget_tokens. Effort ∈ {low, medium, high}.
            body["thinking"] = {"type": "adaptive"}
            body["output_config"] = {"effort": thinking_effort}
        # The Anthropic Messages API is served by the *vendor* proxy host
        # (vendors.llm...), not the OpenAI-compat host (proxy.llm...). Derive
        # the vendor host from base_url by swapping the leading subdomain.
        from urllib.parse import urlsplit, urlunsplit
        sp = urlsplit(self.base_url)
        host = sp.netloc
        if host.startswith("proxy."):
            host = "vendors." + host[len("proxy."):]
        url = urlunsplit((sp.scheme, host, "/apis/anthropic/v1/messages", "", ""))
        r = requests.post(
            url,
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "x-api-key": self.api_key,
                "anthropic-version": "2023-06-01",
                "Content-Type": "application/json",
            },
            json=body,
            timeout=600,
        )
        if not r.ok:
            log().error("Anthropic HTTP %d: %s", r.status_code, r.text[:1500])
        r.raise_for_status()
        data = r.json()
        text_blocks = [b for b in data.get("content", []) if b.get("type") == "text"]
        if not text_blocks:
            log().error("no text content in response: %s", json.dumps(data)[:1500])
            raise RuntimeError("Anthropic returned no text content")
        content = text_blocks[-1]["text"].strip()
        if content.startswith("```"):
            lines = content.splitlines()
            if lines[0].startswith("```"):
                lines = lines[1:]
            if lines and lines[-1].strip() == "```":
                lines = lines[:-1]
            content = "\n".join(lines)
        try:
            return json.loads(content)
        except json.JSONDecodeError:
            log().error("Anthropic returned non-JSON content (first 1500 chars):\n%s", content[:1500])
            raise

    def chat_json(self, system: str, user: str, *, max_tokens: int = 4096,
                  reasoning_effort: str | None = None) -> dict:
        """OpenAI-compatible /v1/chat/completions, response_format=json_object.

        reasoning_effort ∈ {None, "low", "medium", "high"}: passed through to
        LiteLLM, which translates to Anthropic's `thinking.budget_tokens`
        (1024 / 2048 / 4096 respectively).
        """
        body: dict[str, Any] = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "response_format": {"type": "json_object"},
            "max_tokens": max_tokens,
        }
        if reasoning_effort is not None:
            body["reasoning_effort"] = reasoning_effort
            # The Shopify proxy presents Anthropic models behind an OpenAI-shaped
            # route; LiteLLM rejects reasoning_effort unless we whitelist it.
            body["allowed_openai_params"] = ["reasoning_effort"]
        r = requests.post(
            f"{self.base_url}/chat/completions",
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            },
            json=body,
            timeout=300,
        )
        if not r.ok:
            log().error("LLM HTTP %d: %s", r.status_code, r.text[:1000])
        r.raise_for_status()
        data = r.json()
        content = data["choices"][0]["message"]["content"]
        if not content:
            log().error("LLM returned empty content; full response: %s",
                        json.dumps(data, indent=2)[:2000])
            raise RuntimeError("LLM returned empty content")
        # Some providers (Claude via Shopify proxy) wrap JSON in ```json ... ```
        # despite response_format=json_object. Strip a leading/trailing fence.
        stripped = content.strip()
        if stripped.startswith("```"):
            # remove first line (```json or ```) and trailing ```
            lines = stripped.splitlines()
            if lines[0].startswith("```"):
                lines = lines[1:]
            if lines and lines[-1].strip() == "```":
                lines = lines[:-1]
            stripped = "\n".join(lines)
        try:
            return json.loads(stripped)
        except json.JSONDecodeError:
            log().error("LLM returned non-JSON content (first 1500 chars):\n%s", stripped[:1500])
            raise


# --- propose-taxonomy / propose-mapping (stubs to be filled) ---


TAXONOMY_SYSTEM_PROMPT = '''You are designing a category/tag taxonomy for a UK personal finance dataset.

The taxonomy will be used by a categoriser that assigns ONE category per merchant
(stable merchants) or per transaction (polymorphic merchants like Amazon and PayPal).
It may also assign zero or more tags.

Return a JSON object:
{
  "categories": [list of strings],     // 15-30 leaf categories, mutually exclusive
  "tags":       [list of strings],     // 8-15 orthogonal parent tags, multi-valued
  "reasoning":  "<short prose>"
}

Guidelines:
- Categories must be mutually exclusive: any one merchant fits exactly one.
- Tags are multi-valued and orthogonal to categories. They are intended to roll up
  spending across categories (e.g. tag "Food" rolls up Groceries + Restaurants +
  Coffee + Food Delivery; tag "Recurring" rolls up subscriptions across categories).
- Avoid tags that are 1:1 with a category - those add no information.
- Prefer specific over generic for categories: "Groceries", "Restaurants", "Coffee"
  beats one bucket "Food".
- Anchor every proposed category in at least one merchant or polymorphic line item
  visible in the data. Do not invent categories that no transaction matches.
- Use British English spelling where it matters (e.g. "Pet Care" not "Pet Care™").
- Categories and tags are short (1-3 words), Title Case.
'''


def _summarise_merchants_for_llm(aggregate: dict) -> dict:
    """Trim the aggregate to just what the LLM needs for taxonomy proposal."""
    stable = []
    for name, info in aggregate.get("merchants", {}).items():
        samples = [
            {
                "amount": s.get("amount"),
                "description": (s.get("description") or "")[:120],
            }
            for s in (info.get("samples") or [])
        ]
        stable.append({
            "name": name,
            "count": info["count"],
            "total_gbp": info["total_gbp"],
            "type": info["type"],
            "samples": samples,
        })

    polymorphic = []
    for p in aggregate.get("polymorphic_journals", []):
        entry: dict[str, Any] = {
            "merchant": p["merchant"],
            "amount": p["amount"],
            "type": p["type"],
        }
        if p.get("amazon_items"):
            entry["amazon_items"] = [
                {"title": (it.get("title") or "")[:120], "amount": it.get("amount")}
                for it in p["amazon_items"]
            ]
        if p.get("paypal_seller"):
            entry["paypal_seller"] = p["paypal_seller"]
        if not p.get("amazon_items") and not p.get("paypal_seller"):
            entry["description"] = (p.get("description") or "")[:120]
        polymorphic.append(entry)

    return {"stable_merchants": stable, "polymorphic_transactions": polymorphic}


def propose_taxonomy(aggregate: dict, llm: LLMClient, feedback: str | None = None) -> dict:
    summary = _summarise_merchants_for_llm(aggregate)
    parts = [
        "Here is the merchant inventory from a real UK personal finance dataset.",
        "",
        json.dumps(summary, indent=2, ensure_ascii=False),
        "",
    ]
    if feedback:
        parts.extend([
            "User feedback on a previous proposal (incorporate these revisions):",
            feedback,
            "",
        ])
    parts.append("Propose the taxonomy now.")
    user = "\n".join(parts)
    log().info(
        "calling LLM for taxonomy proposal (model=%s, %d stable merchants, %d polymorphic txs)",
        llm.model, len(summary["stable_merchants"]), len(summary["polymorphic_transactions"]),
    )
    # Opus 4.6/4.7 are gated behind the Anthropic Messages API on the proxy;
    # detect by model name and route accordingly.
    if "opus-4-6" in llm.model or "opus-4-7" in llm.model:
        anthropic_model = llm.model.rsplit(":", 1)[-1]  # strip provider prefix
        return llm.anthropic_messages_json(
            TAXONOMY_SYSTEM_PROMPT, user,
            anthropic_model=anthropic_model,
            max_tokens=32768,
            thinking_effort="xhigh",
        )
    return llm.chat_json(TAXONOMY_SYSTEM_PROMPT, user, max_tokens=16384,
                         reasoning_effort="high")


MAPPING_SYSTEM_PROMPT = '''You are mapping merchants to categories and tags from a frozen taxonomy.

For each merchant you are given, return:
- exactly ONE category, picked verbatim from `taxonomy.categories`
- zero or more tags, each picked verbatim from `taxonomy.tags`

Output JSON shape:
{
  "mapping": {
    "<merchant name verbatim>": {
      "category": "<one of taxonomy.categories>",
      "tags": ["<from taxonomy.tags>", ...]
    },
    ...
  }
}

Rules:
- Cover EVERY merchant in the input. Do not skip.
- The merchant key must be the exact string given, verbatim.
- Category and tag strings must be verbatim from the taxonomy. Do not invent.
- Deposits (type: "deposit") map to one of the income categories: Salary,
  Refunds & Reimbursements, Investment Income, Other Income. Apply the Income
  tag.
- Apply the Recurring tag to merchants that look like monthly/periodic bills:
  utilities, subscriptions, mortgage/rent, insurance, mobile/broadband,
  council tax. Use the merchant\'s `count` and `total` as a hint.
- Apply Transport to anything mobility-related (Motoring, Public Transport,
  Taxi & Rideshare, parking, fuel, train, etc.).
- Apply Travel to Air Travel, Hotels & Accommodation, holiday-related spend.
- Apply Food to anything in Groceries / Restaurants & Takeaway / Coffee /
  Pubs & Bars / Food Delivery.
- Apply Pets to anything pet-related.
- Apply Housing to mortgage/rent, council tax, utilities, home & garden
  spend related to the house itself.
- Apply Self Care to healthcare, beauty, personal care, fitness.
- Apply Online Shopping when the merchant is clearly an online retailer
  (e-commerce only, not high-street with a website).
- Apply International when the spend is in a foreign country/currency.
- Apply Work to merchants that are clearly business expenses or
  work-related software/services.
- A merchant can carry multiple tags; tags are orthogonal to categories.
- Tags are optional: a merchant may have zero tags if none apply.
- Use British conventions and spelling.
'''


def _summarise_merchants_for_mapping(aggregate: dict) -> list[dict]:
    out = []
    for name, info in aggregate.get("merchants", {}).items():
        samples = [
            {
                "amount": s.get("amount"),
                "description": (s.get("description") or "")[:120],
            }
            for s in (info.get("samples") or [])
        ]
        out.append({
            "name": name,
            "count": info["count"],
            "total_gbp": info["total_gbp"],
            "type": info["type"],
            "samples": samples,
        })
    return out


def propose_mapping(aggregate: dict, taxonomy: dict, llm: LLMClient,
                    feedback: str | None = None) -> dict:
    merchants = _summarise_merchants_for_mapping(aggregate)
    parts = [
        "Frozen taxonomy:",
        json.dumps(taxonomy, indent=2, ensure_ascii=False),
        "",
        f"Merchant inventory ({len(merchants)} merchants):",
        json.dumps(merchants, indent=2, ensure_ascii=False),
        "",
    ]
    if feedback:
        parts.extend([
            "User feedback on a previous proposal (incorporate these revisions):",
            feedback,
            "",
        ])
    parts.append("Map every merchant now. Return the JSON.")
    user = "\n".join(parts)
    log().info(
        "calling LLM for mapping (model=%s, %d merchants)",
        llm.model, len(merchants),
    )
    if "opus-4-6" in llm.model or "opus-4-7" in llm.model:
        anthropic_model = llm.model.rsplit(":", 1)[-1]
        return llm.anthropic_messages_json(
            MAPPING_SYSTEM_PROMPT, user,
            anthropic_model=anthropic_model,
            max_tokens=49152,
            thinking_effort="xhigh",
        )
    return llm.chat_json(MAPPING_SYSTEM_PROMPT, user, max_tokens=32768,
                         reasoning_effort="high")


# --- run (steady-state) ---


RUNTIME_SYSTEM_PROMPT = '''You categorise one Firefly III personal-finance transaction.

You must return JSON:
{
  "category": "<one of taxonomy.categories>",
  "tags": ["<from taxonomy.tags>", ...],
  "confidence": 0.0,
  "reason": "short explanation"
}

Rules:
- Pick exactly one category from the provided taxonomy.
- Tags are optional but, if present, must be picked verbatim from taxonomy.tags.
- Use the enricher block heavily: Amazon item titles and PayPal seller names are
  more informative than opaque bank merchant names.
- Deposits should usually be Salary, Refunds & Reimbursements, Investment Income,
  Other Income, or Mortgage & Rent (when it is a rent/household contribution).
- Be conservative with confidence. Use >= 0.8 only when the category is clear.
- Do not invent categories or tags.
'''


def merge_tags(existing: list[str] | None, added: list[str]) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for tag in (existing or []) + added:
        if tag is None:
            continue
        if tag in seen:
            continue
        seen.add(tag)
        out.append(tag)
    return out


def validate_taxonomy(taxonomy: dict, merchant_map: dict) -> None:
    categories = set(taxonomy.get("categories") or [])
    tags = set(taxonomy.get("tags") or [])
    if not categories:
        raise ValueError("taxonomy has no categories")
    for merchant, info in merchant_map.items():
        category = info.get("category")
        if category not in categories:
            raise ValueError(f"merchant {merchant!r} has invalid category {category!r}")
        for tag in info.get("tags") or []:
            if tag not in tags:
                raise ValueError(f"merchant {merchant!r} has invalid tag {tag!r}")


def merchant_for(inner: dict) -> str:
    if inner.get("type") == "withdrawal":
        return inner.get("destination_name") or ""
    if inner.get("type") == "deposit":
        return inner.get("source_name") or ""
    return ""


def asset_for(inner: dict) -> str:
    if inner.get("type") == "withdrawal":
        return inner.get("source_name") or ""
    if inner.get("type") == "deposit":
        return inner.get("destination_name") or ""
    return ""


def classify_with_llm(inner: dict, enricher: dict, taxonomy: dict, llm: LLMClient) -> dict:
    context = {
        "taxonomy": taxonomy,
        "transaction": {
            "type": inner.get("type"),
            "merchant": merchant_for(inner),
            "asset_account": asset_for(inner),
            "amount_gbp": float(inner.get("amount") or 0),
            "description": inner.get("description"),
            "date": inner.get("date"),
            "enricher": enricher,
        },
    }
    return llm.chat_json(
        RUNTIME_SYSTEM_PROMPT,
        json.dumps(context, indent=2, ensure_ascii=False),
        max_tokens=2048,
    )


def normalise_llm_result(raw: dict, taxonomy: dict) -> dict:
    categories = set(taxonomy.get("categories") or [])
    valid_tags = set(taxonomy.get("tags") or [])
    category = raw.get("category")
    tags = [t for t in (raw.get("tags") or []) if t in valid_tags]
    try:
        confidence = float(raw.get("confidence", 0.0))
    except (TypeError, ValueError):
        confidence = 0.0
    confidence = max(0.0, min(1.0, confidence))
    reason = str(raw.get("reason") or "")[:1000]
    if category not in categories:
        return {
            "category": None,
            "tags": tags,
            "confidence": 0.0,
            "reason": f"invalid category from model: {category!r}; {reason}",
        }
    return {
        "category": category,
        "tags": tags,
        "confidence": confidence,
        "reason": reason,
    }


def process_journal_run(
    j: dict,
    firefly: FireflyClient,
    llm: LLMClient,
    taxonomy: dict,
    merchant_map: dict,
    dry_run: bool,
    force: bool,
) -> str:
    attrs = j["attributes"]
    group_id = int(j["id"])
    inner = attrs["transactions"][0]
    journal_id = int(inner["transaction_journal_id"])
    ttype = inner.get("type")
    notes = inner.get("notes") or ""

    if ttype not in ("withdrawal", "deposit"):
        return f"skip:type id={journal_id} type={ttype}"
    if inner.get("category_name") and not force:
        return f"skip:category_exists id={journal_id} category={inner.get('category_name')}"
    if has_categoriser_block(notes) and not force:
        return f"skip:already_attempted id={journal_id}"

    merchant = merchant_for(inner)
    existing_tags = inner.get("tags") or []
    enricher = existing_enricher_block(notes)

    if (not is_polymorphic(merchant)) and merchant in merchant_map:
        mapped = merchant_map[merchant]
        category = mapped["category"]
        tags = mapped.get("tags") or []
        audit = {
            "version": CATEGORISER_VERSION,
            "path": "lookup",
            "merchant": merchant,
            "category": category,
            "tags": tags,
            "confidence": 1.0,
            "applied": True,
        }
    else:
        raw = classify_with_llm(inner, enricher, taxonomy, llm)
        result = normalise_llm_result(raw, taxonomy)
        category = result["category"]
        tags = result["tags"]
        applied = bool(category) and result["confidence"] >= 0.8
        audit = {
            "version": CATEGORISER_VERSION,
            "path": "llm",
            "merchant": merchant,
            "category": category,
            "tags": tags,
            "confidence": result["confidence"],
            "applied": applied,
            "model": llm.model,
            "reason": result["reason"],
        }
        if not applied:
            tags = merge_tags(tags, ["needs-review"])

    new_tags = merge_tags(existing_tags, tags)
    new_notes = merge_categoriser(notes, audit)
    fields: dict[str, Any] = {
        "notes": new_notes,
        "tags": new_tags,
    }
    if audit["applied"]:
        fields["category_name"] = category

    if dry_run:
        return (
            f"dryrun id={journal_id} path={audit['path']} merchant={merchant!r} "
            f"category={category!r} applied={audit['applied']} tags={tags}"
        )
    firefly.update_journal(group_id, journal_id, fields)
    return (
        f"ok id={journal_id} path={audit['path']} merchant={merchant!r} "
        f"category={category!r} applied={audit['applied']}"
    )


def run_categoriser(
    firefly: FireflyClient,
    llm: LLMClient,
    taxonomy: dict,
    merchant_map: dict,
    dry_run: bool,
    force: bool,
    limit: int | None,
) -> int:
    validate_taxonomy(taxonomy, merchant_map)
    journals: list[dict] = []
    for q in ("type:withdrawal", "type:deposit"):
        log().info("fetching %r", q)
        journals.extend(firefly.search_transactions(q))
    log().info("found %d withdrawal/deposit journals", len(journals))

    processed = 0
    for j in journals:
        try:
            result = process_journal_run(
                j, firefly, llm, taxonomy, merchant_map, dry_run, force,
            )
            print(result, file=sys.stderr)
            if result.startswith(("ok ", "dryrun ")):
                processed += 1
                if limit is not None and processed >= limit:
                    log().info("limit reached (%d)", limit)
                    break
        except Exception as e:
            log().exception("error on journal group=%s: %s", j.get("id"), e)
        time.sleep(0.1)
    log().info("processed %d journals", processed)
    return 0


# --- main / argparse ---


def cmd_aggregate(args, firefly: FireflyClient) -> int:
    out = aggregate_journals(firefly)
    json.dump(out, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


def cmd_propose_taxonomy(args, firefly: FireflyClient, llm: LLMClient) -> int:
    with open(args.aggregate_file) as f:
        aggregate = json.load(f)
    out = propose_taxonomy(aggregate, llm, feedback=args.feedback)
    json.dump(out, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


def cmd_propose_mapping(args, firefly: FireflyClient, llm: LLMClient) -> int:
    with open(args.aggregate_file) as f:
        aggregate = json.load(f)
    with open(args.taxonomy_file) as f:
        taxonomy = json.load(f)
    out = propose_mapping(aggregate, taxonomy, llm, feedback=args.feedback)
    json.dump(out, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


def cmd_run(args, firefly: FireflyClient, llm: LLMClient) -> int:
    if not args.taxonomy_file:
        raise ValueError("--taxonomy-file or CATEGORISER_TAXONOMY_FILE is required")
    if not args.merchant_map_file:
        raise ValueError("--merchant-map-file or CATEGORISER_MAP_FILE is required")
    with open(args.taxonomy_file) as f:
        taxonomy = json.load(f)
    with open(args.merchant_map_file) as f:
        merchant_map = json.load(f)
    return run_categoriser(
        firefly, llm, taxonomy, merchant_map,
        dry_run=args.dry_run,
        force=args.force,
        limit=args.limit,
    )


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--firefly-url", default=os.environ.get(
        "FIREFLY_URL", "http://firefly.nexus.hosts.10.0.0.2.nip.io"))
    p.add_argument("--firefly-token-file", default=os.environ.get(
        "FIREFLY_TOKEN_FILE", "/var/lib/firefly-importer/access-token.txt"))
    p.add_argument("--llm-endpoint", default=os.environ.get(
        "LLM_ENDPOINT", "https://proxy.llm.surma.technology/v1"))
    p.add_argument("--llm-key-file", default=os.environ.get(
        "LLM_KEY_FILE", "/var/lib/scout/llm-proxy-client-key"))
    p.add_argument("--llm-model", default=os.environ.get(
        "LLM_MODEL", "shopify:anthropic:claude-haiku-4-5"))
    p.add_argument("-v", "--verbose", action="store_true")

    sub = p.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("aggregate", help="inventory merchants from Firefly")
    sp.set_defaults(fn=cmd_aggregate, needs_llm=False)

    sp = sub.add_parser("propose-taxonomy", help="LLM proposes categories/tags")
    sp.add_argument("aggregate_file")
    sp.add_argument("--feedback", default=None,
                    help="revisions to a previous proposal, fed back to the LLM")
    sp.set_defaults(fn=cmd_propose_taxonomy, needs_llm=True)

    sp = sub.add_parser("propose-mapping", help="LLM proposes merchant→category mapping")
    sp.add_argument("aggregate_file")
    sp.add_argument("taxonomy_file")
    sp.add_argument("--feedback", default=None,
                    help="revisions to a previous proposal, fed back to the LLM")
    sp.set_defaults(fn=cmd_propose_mapping, needs_llm=True)

    sp = sub.add_parser("run", help="steady-state: categorise journals")
    sp.add_argument("--taxonomy-file", default=os.environ.get(
        "CATEGORISER_TAXONOMY_FILE", ""))
    sp.add_argument("--merchant-map-file", default=os.environ.get(
        "CATEGORISER_MAP_FILE", ""))
    sp.add_argument("--dry-run", action="store_true")
    sp.add_argument("--force", action="store_true",
                    help="reprocess even if category/frontmatter already exists")
    sp.add_argument("--limit", type=int, default=None,
                    help="process at most N journals (after skips)")
    sp.set_defaults(fn=cmd_run, needs_llm=True)

    args = p.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(message)s",
        stream=sys.stderr,
    )

    with open(args.firefly_token_file) as f:
        token = f.read().strip()
    firefly = FireflyClient(base_url=args.firefly_url.rstrip("/"), token=token)

    if args.needs_llm:
        with open(args.llm_key_file) as f:
            llm_key = f.read().strip()
        llm = LLMClient(
            base_url=args.llm_endpoint.rstrip("/"),
            api_key=llm_key,
            model=args.llm_model,
        )
        return args.fn(args, firefly, llm)
    else:
        return args.fn(args, firefly)


if __name__ == "__main__":
    sys.exit(main())
