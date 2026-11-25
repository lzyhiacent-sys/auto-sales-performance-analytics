-- Star schema for the Nordline France VN (new vehicle) sales dataset.
-- Dimensions: dealer, model, model x energy. Facts: orders (PO), registrations,
-- month-end stock, monthly targets, total market by segment.

DROP TABLE IF EXISTS fact_market;
DROP TABLE IF EXISTS fact_targets;
DROP TABLE IF EXISTS fact_stock;
DROP TABLE IF EXISTS fact_registrations;
DROP TABLE IF EXISTS fact_orders;
DROP TABLE IF EXISTS dim_model_energy;
DROP TABLE IF EXISTS dim_model;
DROP TABLE IF EXISTS dim_dealer;

CREATE TABLE dim_dealer (
    dealer_id    TEXT PRIMARY KEY,
    dealer_name  TEXT NOT NULL,
    city         TEXT NOT NULL,
    region       TEXT NOT NULL,
    size_class   TEXT NOT NULL CHECK (size_class IN ('S', 'M', 'L'))
);

CREATE TABLE dim_model (
    model_id          TEXT PRIMARY KEY,
    model             TEXT NOT NULL,
    segment           TEXT NOT NULL,
    body              TEXT NOT NULL,
    base_price_eur    REAL NOT NULL,
    import_lead_days  INTEGER NOT NULL
);

CREATE TABLE dim_model_energy (
    model_id    TEXT NOT NULL REFERENCES dim_model (model_id),
    energy      TEXT NOT NULL CHECK (energy IN ('BEV', 'PHEV', 'HEV')),
    powertrain  TEXT NOT NULL,
    PRIMARY KEY (model_id, energy)
);

CREATE TABLE fact_orders (
    order_id           TEXT PRIMARY KEY,
    order_date         DATE NOT NULL,
    dealer_id          TEXT NOT NULL REFERENCES dim_dealer (dealer_id),
    model_id           TEXT NOT NULL REFERENCES dim_model (model_id),
    energy             TEXT NOT NULL,
    trim               TEXT NOT NULL,
    channel            TEXT NOT NULL CHECK (channel IN ('Private', 'Fleet', 'Direct')),
    list_price_eur     REAL NOT NULL,
    discount_pct       REAL NOT NULL,
    net_price_eur      REAL NOT NULL,
    dealer_margin_eur  REAL NOT NULL,
    order_status       TEXT NOT NULL CHECK (order_status IN ('Registered', 'Cancelled', 'Open'))
);

CREATE TABLE fact_registrations (
    registration_id    TEXT PRIMARY KEY,
    order_id           TEXT NOT NULL UNIQUE REFERENCES fact_orders (order_id),
    registration_date  DATE NOT NULL,
    delivery_date      DATE NOT NULL
);

CREATE TABLE fact_stock (
    snapshot_date  DATE NOT NULL,
    dealer_id      TEXT NOT NULL REFERENCES dim_dealer (dealer_id),
    model_id       TEXT NOT NULL REFERENCES dim_model (model_id),
    stock_units    INTEGER NOT NULL,
    PRIMARY KEY (snapshot_date, dealer_id, model_id)
);

CREATE TABLE fact_targets (
    month                 DATE NOT NULL,
    dealer_id             TEXT NOT NULL REFERENCES dim_dealer (dealer_id),
    target_registrations  INTEGER NOT NULL,
    PRIMARY KEY (month, dealer_id)
);

CREATE TABLE fact_market (
    month                 DATE NOT NULL,
    segment               TEXT NOT NULL,
    market_registrations  INTEGER NOT NULL,
    PRIMARY KEY (month, segment)
);

CREATE INDEX ix_orders_dealer_date ON fact_orders (dealer_id, order_date);
CREATE INDEX ix_reg_date ON fact_registrations (registration_date);
