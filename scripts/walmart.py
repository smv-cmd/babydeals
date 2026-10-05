#!/usr/bin/env python3
"""Fetch discounted baby clothing from the Walmart Affiliate API and write walmart_deals.json.

Credentials (never committed) come from ~/.config/babydeals/walmart.env:
    WALMART_CONSUMER_ID=...            # from developer.walmart.com
    WALMART_KEY_VERSION=1              # version shown when you uploaded your public key
    WALMART_PRIVATE_KEY_PATH=/Users/you/.config/babydeals/walmart_private.pem   # PKCS#8 PEM
    WALMART_PUBLISHER_ID=...           # optional: Impact publisher id for tracked links

Requires only python3 and /usr/bin/openssl. Exits 0 with no output file if credentials are missing.
"""
import base64, json, os, subprocess, sys, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "walmart_deals.json")
ENV = os.path.expanduser("~/.config/babydeals/walmart.env")
BASE = "https://developer.api.walmart.com/api-proxy/service/affil/product/v2/search"
QUERIES = ["baby clothes", "baby bodysuit", "baby sleeper pajamas", "baby romper", "baby outfit set",
           "baby jacket", "baby pants", "baby dress", "baby socks hat"]
MIN_DISCOUNT = 10  # percent

CATS = [("sleep", "Sleepwear"), ("pajama", "Sleepwear"), ("bodysuit", "Bodysuits"), ("romper", "Rompers"),
        ("dress", "Dresses"), ("jacket", "Outerwear"), ("coat", "Outerwear"), ("pant", "Bottoms"),
        ("legging", "Bottoms"), ("set", "Sets"), ("outfit", "Sets"), ("hat", "Accessories"),
        ("sock", "Accessories"), ("shirt", "Tops"), ("tee", "Tops"), ("top", "Tops")]


def load_env():
    cfg = {}
    if os.path.exists(ENV):
        for line in open(ENV):
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                cfg[k.strip()] = v.strip().strip('"')
    return cfg


def sign(consumer_id, key_version, key_path):
    ts = str(int(time.time() * 1000))
    data = f"{consumer_id}\n{ts}\n{key_version}\n".encode()
    sig = subprocess.run(["/usr/bin/openssl", "dgst", "-sha256", "-sign", key_path],
                         input=data, capture_output=True, check=True).stdout
    return ts, base64.b64encode(sig).decode()


def category(name):
    n = name.lower()
    return next((c for k, c in CATS if k in n), "Sets")


def main():
    cfg = load_env()
    need = ("WALMART_CONSUMER_ID", "WALMART_KEY_VERSION", "WALMART_PRIVATE_KEY_PATH")
    if any(not cfg.get(k) for k in need):
        print("walmart.py: credentials not configured; skipping")
        return 0
    seen, deals = set(), []
    for q in QUERIES:
        ts, sig = sign(cfg["WALMART_CONSUMER_ID"], cfg["WALMART_KEY_VERSION"], os.path.expanduser(cfg["WALMART_PRIVATE_KEY_PATH"]))
        params = {"query": q, "numItems": "25", "sort": "relevance"}
        if cfg.get("WALMART_PUBLISHER_ID"):
            params["publisherId"] = cfg["WALMART_PUBLISHER_ID"]
        req = urllib.request.Request(BASE + "?" + urllib.parse.urlencode(params), headers={
            "WM_CONSUMER.ID": cfg["WALMART_CONSUMER_ID"], "WM_CONSUMER.INTIMESTAMP": ts,
            "WM_SEC.KEY_VERSION": cfg["WALMART_KEY_VERSION"], "WM_SEC.AUTH_SIGNATURE": sig,
            "Accept": "application/json"})
        try:
            items = json.load(urllib.request.urlopen(req, timeout=30)).get("items", [])
        except Exception as e:
            print(f"walmart.py: query '{q}' failed: {e}", file=sys.stderr)
            continue
        for it in items:
            now, was = it.get("salePrice"), it.get("msrp")
            if not (now and was and now < was) or (1 - now / was) * 100 < MIN_DISCOUNT:
                continue
            if it.get("itemId") in seen:
                continue
            seen.add(it.get("itemId"))
            deals.append({"name": it["name"], "store": "Walmart", "cat": category(it["name"]), "size": "Baby",
                          "was": round(float(was), 2), "now": round(float(now), 2), "emoji": "👶",
                          "url": it.get("productTrackingUrl") or it.get("productUrl"),
                          "image": it.get("mediumImage") or it.get("largeImage") or it.get("thumbnailImage")})
    json.dump({"fetched": time.strftime("%Y-%m-%d"), "deals": deals}, open(OUT, "w"), indent=1)
    print(f"walmart.py: wrote {len(deals)} deals")
    return 0


if __name__ == "__main__":
    sys.exit(main())
