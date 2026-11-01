import csv
import io
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import quote
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[2]
OUTPUT_PATH = ROOT / "market-data.json"
USER_AGENT = "Mozilla/5.0 (compatible; FinanceDashboard/1.0)"
SERIES_SPECS = {
    "dxy": ("yahoo", "DX-Y.NYB"),
    "us10y": ("fred", "DGS10"),
    "us2y": ("fred", "DGS2"),
    "spx": ("yahoo", "^GSPC"),
    "ndx": ("yahoo", "^NDX"),
}


def read_url(url: str) -> str:
    request = Request(url, headers={"User-Agent": USER_AGENT})
    with urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8-sig")


def fetch_yahoo(symbol: str) -> list[dict[str, float | str]]:
    encoded_symbol = quote(symbol, safe="")
    url = (
        "https://query1.finance.yahoo.com/v8/finance/chart/"
        f"{encoded_symbol}?range=2mo&interval=1d"
    )
    payload = json.loads(read_url(url))
    result = payload["chart"]["result"][0]
    timestamps = result["timestamp"]
    closes = result["indicators"]["quote"][0]["close"]
    points = []
    for timestamp, close in zip(timestamps, closes):
        if close is None:
            continue
        points.append({
            "date": datetime.fromtimestamp(timestamp, timezone.utc).date().isoformat(),
            "value": float(close),
        })
    points = points[-30:]
    if len(points) < 2:
        raise ValueError(f"Not enough Yahoo Finance data for {symbol}")
    return points


def fetch_fred(series_id: str) -> list[dict[str, float | str]]:
    start_date = (datetime.now(timezone.utc) - timedelta(days=70)).date().isoformat()
    url = f"https://fred.stlouisfed.org/graph/fredgraph.csv?id={series_id}&cosd={start_date}"
    reader = csv.DictReader(io.StringIO(read_url(url)))
    points = []
    for row in reader:
        raw_value = (row.get(series_id) or "").strip()
        if not raw_value or raw_value == ".":
            continue
        points.append({"date": row["observation_date"], "value": float(raw_value)})
    points = points[-30:]
    if len(points) < 2:
        raise ValueError(f"Not enough FRED data for {series_id}")
    return points


def main() -> None:
    series = {}
    sources = {}
    failures = {}
    for key, (provider, symbol) in SERIES_SPECS.items():
        try:
            series[key] = fetch_yahoo(symbol) if provider == "yahoo" else fetch_fred(symbol)
            sources[key] = "Yahoo Finance" if provider == "yahoo" else "FRED"
            print(f"Fetched {key}: {len(series[key])} daily points")
        except Exception as error:
            failures[key] = str(error)
            print(f"Could not fetch {key}: {error}", file=sys.stderr)

    if not series:
        raise SystemExit("No market data was retrieved; refusing to publish an empty feed.")

    payload = {
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "sources": sources,
        "series": series,
        "failures": failures,
    }
    temporary_path = OUTPUT_PATH.with_suffix(".json.tmp")
    temporary_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary_path.replace(OUTPUT_PATH)
    print(f"Wrote {OUTPUT_PATH.name} with {len(series)} series")


if __name__ == "__main__":
    main()