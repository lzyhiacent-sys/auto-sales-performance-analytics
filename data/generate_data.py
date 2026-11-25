"""
Generate a synthetic new-vehicle (VN) sales dataset for a fictional car brand
("Nordline") sold through a French dealer network.

All figures are synthetic. They are built to behave like real dealer data
(seasonality, cancellations, order-to-registration lead times, discounts,
stock) so that the SQL and dashboard work on realistic patterns.

Usage:
    python data/generate_data.py          # writes CSV files to data/raw/
"""

from pathlib import Path

import numpy as np
import pandas as pd

SEED = 42
START = pd.Timestamp("2025-01-01")
END = pd.Timestamp("2026-09-30")          # last day of the data window
ORDER_START = pd.Timestamp("2024-10-01")  # orders start earlier so Jan 2025 registrations are complete
OUT = Path(__file__).resolve().parent / "raw"

rng = np.random.default_rng(SEED)

# --------------------------------------------------------------------------
# Reference data: models, trims, regions, dealers
# --------------------------------------------------------------------------
MODELS = [
    # model_id, model, segment, body, base_price_eur, import_lead_days
    ("M01", "Aster",  "B-SUV",     "SUV",       28900, 38),
    ("M02", "Lumen",  "C-Hatch",   "Hatchback", 31900, 42),
    ("M03", "Orion",  "C-SUV",     "SUV",       38900, 46),
    ("M04", "Vega",   "D-Sedan",   "Sedan",     46900, 55),
    ("M05", "Atlas",  "LCV",       "Van",       41900, 60),
]
# which energies each model is offered in, with its order share
MODEL_ENERGY = {
    "M01": {"BEV": 0.55, "HEV": 0.45},
    "M02": {"BEV": 0.70, "PHEV": 0.30},
    "M03": {"BEV": 0.40, "PHEV": 0.45, "HEV": 0.15},
    "M04": {"BEV": 0.65, "PHEV": 0.35},
    "M05": {"BEV": 1.00},
}
ENERGY_PRICE_DELTA = {"BEV": 3000, "PHEV": 1500, "HEV": 0}
POWERTRAIN = {"BEV": "Electric", "PHEV": "Plug-in hybrid", "HEV": "Hybrid"}
TRIMS = {"Comfort": (0.40, 0), "Design": (0.40, 2500), "Premium": (0.20, 5500)}
MODEL_MIX = np.array([0.30, 0.22, 0.28, 0.10, 0.10])

REGIONS = {
    "Ile-de-France":            ["Paris Est", "Paris Ouest", "Versailles", "Creteil", "Cergy", "Evry", "Saint-Denis"],
    "Auvergne-Rhone-Alpes":     ["Lyon Nord", "Lyon Sud", "Grenoble", "Clermont-Ferrand", "Annecy"],
    "Provence-Alpes-Cote d'Azur": ["Marseille", "Nice", "Toulon", "Aix-en-Provence"],
    "Occitanie":                ["Toulouse", "Montpellier", "Nimes", "Perpignan"],
    "Nouvelle-Aquitaine":       ["Bordeaux", "Bayonne", "Limoges", "La Rochelle"],
    "Hauts-de-France":          ["Lille", "Amiens", "Valenciennes", "Dunkerque"],
    "Grand Est":                ["Strasbourg", "Metz", "Nancy", "Reims"],
    "Ouest":                    ["Nantes", "Rennes", "Angers", "Brest", "Le Mans"],
}
CHANNELS = {"Private": 0.55, "Fleet": 0.30, "Direct": 0.15}
CHANNEL_DISCOUNT = {"Private": 0.04, "Fleet": 0.09, "Direct": 0.02}


def build_dealers() -> pd.DataFrame:
    rows, i = [], 1
    for region, cities in REGIONS.items():
        for city in cities:
            size = rng.choice(["S", "M", "L"], p=[0.30, 0.45, 0.25])
            potential = {"S": 14, "M": 24, "L": 38}[size] * rng.uniform(0.85, 1.15)
            rows.append({
                "dealer_id": f"D{i:03d}",
                "dealer_name": f"Nordline {city}",
                "city": city,
                "region": region,
                "size_class": size,
                # hidden behaviour drivers (not exported)
                "_potential": potential,          # monthly order potential
                "_execution": rng.normal(1.0, 0.13),   # sells above/below potential
                "_cancel": rng.uniform(0.04, 0.13),    # order cancellation rate
                "_delay": rng.normal(0, 7),            # extra delivery delay (days)
                "_discount_bias": rng.normal(0, 0.015),
            })
            i += 1
    return pd.DataFrame(rows)


def season(month: int) -> float:
    # French VN market: strong March/June/September, weak August
    return {1: 0.85, 2: 0.92, 3: 1.15, 4: 1.00, 5: 0.95, 6: 1.12,
            7: 0.95, 8: 0.62, 9: 1.10, 10: 1.02, 11: 0.98, 12: 1.08}[month]


def build_orders(dealers: pd.DataFrame) -> pd.DataFrame:
    months = pd.period_range(ORDER_START, END, freq="M")
    rows, oid = [], 1
    model_ids = [m[0] for m in MODELS]
    base_price = {m[0]: m[4] for m in MODELS}
    for _, d in dealers.iterrows():
        for k, p in enumerate(months):
            growth = 1 + 0.012 * (k - 3)                 # brand ramp-up (k=3 is Jan 2025)
            lam = d._potential * d._execution * season(p.month) * growth
            n = rng.poisson(max(lam, 1))
            days = rng.integers(1, p.days_in_month + 1, size=n)
            for day in days:
                model = rng.choice(model_ids, p=MODEL_MIX)
                energies = MODEL_ENERGY[model]
                energy = rng.choice(list(energies), p=list(energies.values()))
                trim = rng.choice(list(TRIMS), p=[t[0] for t in TRIMS.values()])
                channel = "Fleet" if model == "M05" and rng.random() < 0.7 else \
                    rng.choice(list(CHANNELS), p=list(CHANNELS.values()))
                list_price = base_price[model] + ENERGY_PRICE_DELTA[energy] + TRIMS[trim][1]
                disc = max(0.0, rng.normal(CHANNEL_DISCOUNT[channel] + d._discount_bias, 0.015))
                disc = round(min(disc, 0.18), 4)
                net = round(list_price * (1 - disc), 2)
                # dealer gross margin: base 11% of list, eroded by discount
                margin = round(list_price * 0.11 - list_price * disc * 0.6 + rng.normal(0, 150), 2)
                rows.append({
                    "order_id": f"PO{oid:06d}",
                    "order_date": pd.Timestamp(p.year, p.month, int(day)),
                    "dealer_id": d.dealer_id,
                    "model_id": model,
                    "energy": energy,
                    "trim": trim,
                    "channel": channel,
                    "list_price_eur": list_price,
                    "discount_pct": disc,
                    "net_price_eur": net,
                    "dealer_margin_eur": margin,
                    "x_cancel": d._cancel,
                    "x_delay": d._delay,
                })
                oid += 1
    return pd.DataFrame(rows)


def build_registrations(orders: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    lead = {m[0]: m[5] for m in MODELS}
    status, reg_rows = [], []
    for o in orders.itertuples():
        if rng.random() < o.x_cancel:
            status.append("Cancelled")
            continue
        days = max(7, int(rng.gamma(6, (lead[o.model_id] + o.x_delay) / 6)))
        reg_date = o.order_date + pd.Timedelta(days=days)
        if reg_date > END:
            status.append("Open")          # ordered, not yet registered
            continue
        status.append("Registered")
        reg_rows.append({
            "registration_id": f"RG{len(reg_rows) + 1:06d}",
            "order_id": o.order_id,
            "registration_date": reg_date,
            "delivery_date": reg_date + pd.Timedelta(days=int(rng.integers(2, 10))),
        })
    orders = orders.assign(order_status=status)
    return orders, pd.DataFrame(reg_rows)


def build_stock(orders: pd.DataFrame, regs: pd.DataFrame, dealers: pd.DataFrame) -> pd.DataFrame:
    """Month-end stock of new vehicles per dealer and model."""
    r = regs.merge(orders[["order_id", "dealer_id", "model_id"]], on="order_id")
    r["month"] = r.registration_date.dt.to_period("M")
    monthly = r.groupby(["dealer_id", "model_id", "month"]).size()
    rows = []
    for _, d in dealers.iterrows():
        for m in [x[0] for x in MODELS]:
            for p in pd.period_range(START, END, freq="M"):
                sold = monthly.get((d.dealer_id, m, p), 0)
                # dealers carry 1-3 months of stock, some overstock
                cover = rng.uniform(0.8, 1.6) * (1.6 if d._execution < 0.9 else 1.0)
                rows.append({
                    "snapshot_date": p.to_timestamp(how="end").normalize(),
                    "dealer_id": d.dealer_id,
                    "model_id": m,
                    "stock_units": int(round(max(sold, 1) * cover + rng.integers(0, 3))),
                })
    return pd.DataFrame(rows)


def build_targets(dealers: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for _, d in dealers.iterrows():
        for k, p in enumerate(pd.period_range(START, END, freq="M")):
            tgt = d._potential * season(p.month) * (1 + 0.012 * k) * 0.92
            rows.append({
                "month": p.to_timestamp(),
                "dealer_id": d.dealer_id,
                "target_registrations": int(round(tgt)),
            })
    return pd.DataFrame(rows)


def build_market(regs: pd.DataFrame, orders: pd.DataFrame) -> pd.DataFrame:
    """Total French market registrations per segment and month (synthetic)."""
    seg = {m[0]: m[2] for m in MODELS}
    r = regs.merge(orders[["order_id", "model_id"]], on="order_id")
    r["segment"] = r.model_id.map(seg)
    r["month"] = r.registration_date.dt.to_period("M").dt.to_timestamp()
    brand = r.groupby(["segment", "month"]).size()
    share = {"B-SUV": 0.028, "C-Hatch": 0.021, "C-SUV": 0.025, "D-Sedan": 0.034, "LCV": 0.012}
    rows = []
    for (s, mth), n in brand.items():
        rows.append({"month": mth, "segment": s,
                     "market_registrations": int(n / (share[s] * rng.uniform(0.85, 1.15)))})
    return pd.DataFrame(rows)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    dealers = build_dealers()
    orders = build_orders(dealers)
    orders, regs = build_registrations(orders)
    stock = build_stock(orders, regs, dealers)
    targets = build_targets(dealers)
    market = build_market(regs, orders)

    models = pd.DataFrame(MODELS, columns=["model_id", "model", "segment", "body",
                                           "base_price_eur", "import_lead_days"])
    versions = pd.DataFrame(
        [(m, e, POWERTRAIN[e]) for m, es in MODEL_ENERGY.items() for e in es],
        columns=["model_id", "energy", "powertrain"])

    public = [c for c in dealers.columns if not c.startswith("_")]
    dealers[public].to_csv(OUT / "dim_dealer.csv", index=False)
    models.to_csv(OUT / "dim_model.csv", index=False)
    versions.to_csv(OUT / "dim_model_energy.csv", index=False)
    orders.drop(columns=["x_cancel", "x_delay"]).to_csv(OUT / "fact_orders.csv", index=False)
    regs.to_csv(OUT / "fact_registrations.csv", index=False)
    stock.to_csv(OUT / "fact_stock.csv", index=False)
    targets.to_csv(OUT / "fact_targets.csv", index=False)
    market.to_csv(OUT / "fact_market.csv", index=False)

    print(f"dealers={len(dealers)} orders={len(orders)} registrations={len(regs)} "
          f"stock_rows={len(stock)}")


if __name__ == "__main__":
    main()
