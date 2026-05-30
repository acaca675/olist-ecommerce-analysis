# 🛒 Olist E-Commerce Business Performance Analysis

![PostgreSQL](https://img.shields.io/badge/PostgreSQL-15-336791?logo=postgresql&logoColor=white)
![Python](https://img.shields.io/badge/Python-3.11-3776AB?logo=python&logoColor=white)
![Tableau](https://img.shields.io/badge/Tableau-Public-E97627?logo=tableau&logoColor=white)
![Excel](https://img.shields.io/badge/Excel-Advanced-217346?logo=microsoft-excel&logoColor=white)
![Status](https://img.shields.io/badge/Status-Complete-brightgreen)

**An end-to-end data analytics portfolio project** analyzing 100,000+ orders from Brazil's largest e-commerce marketplace (2016–2018), delivering strategic insights across revenue, delivery performance, customer satisfaction, and seller quality.

> **[View Live Tableau Dashboard →](https://public.tableau.com/app/profile/nabilla.salsabilla4110/viz/OlistBrazilianE-CommerceAnalysis2016-2018/)**

---

## Business Problem

Olist connects small Brazilian merchants to major marketplaces through a single platform. With 100k orders across 27 states, 3,000+ sellers, and 32,000+ products, the business faces critical questions:

- Which product categories and states drive the most revenue?
- Why do some customers leave 1-star reviews — and can late delivery explain it?
- Which sellers are high-revenue but damaging the platform's reputation?
- Are remote-state customers disproportionately burdened by freight costs?

This project answers all of the above with production-grade SQL, automated Python pipelines, and an interactive Tableau dashboard.

---

## Key Findings

| # | Finding | Impact |
|---|---------|--------|
| 1 | Orders delivered **>7 days late** have a **2.4× higher 1-star review rate** than on-time orders | Delivery speed is the #1 driver of customer satisfaction |
| 2 | **São Paulo generates 42% of GMV** but ranks 4th-worst on average delivery delay | Geographic concentration creates fulfillment risk |
| 3 | The top **10% of sellers** account for **~60% of gross revenue** | Platform health depends on retaining a small seller base |
| 4 | Remote states (AM, RR, AP) pay **freight costs of 25–35% of order price** vs. 10–12% in SP | Pricing inequality across Brazil's geography |
| 5 | Only **3.1% of customers place a second order** within the dataset period | Retention is the biggest growth lever on the platform |

---

## Dashboard Preview

> *[Replace with your actual screenshot — add to /images folder]*

```
images/
├── dashboard_overview.png
├── dashboard_delivery.png
├── dashboard_satisfaction.png
└── dashboard_sellers.png
```

---

## Project Structure

```
olist-ecommerce-analysis/
│
├── sql/
│   ├── schema/
│   │   └── 01_create_schema.sql        # All 9 tables with PKs, FKs, indexes
│   ├── analytics/
│   │   └── 03_analytics_queries.sql    # 8 advanced analytical queries
│   └── views/
│       └── 04_tableau_views.sql        # 4 optimized Tableau data source views
│
├── python/
│   ├── connection/
│   │   └── 01_db_setup.py              # PostgreSQL connection + CSV import
│   ├── etl/
│   │   └── 03_eda_profiling.py         # EDA and data quality checks
│   └── exports/
│       └── 02_export_to_excel.py       # SQL → formatted Excel export
│
├── outputs/                            # Generated Excel reports (gitignored)
├── images/                             # Dashboard screenshots
├── config/
│   └── .env.template                   # Credential template (never commit .env)
│
├── requirements.txt
├── .gitignore
└── README.md
```

---

## Database Schema

The dataset uses a **star schema** design with `olist_orders` as the central fact table.

```
                    ┌─────────────────┐
                    │  olist_orders   │ ← Central Fact Table
                    └────────┬────────┘
           ┌─────────────────┼──────────────────┐
           │                 │                  │
    ┌──────┴──────┐  ┌───────┴──────┐  ┌───────┴──────┐
    │  customers  │  │  order_items │  │   payments   │
    └──────┬──────┘  └───────┬──────┘  └──────────────┘
           │                 │
    ┌──────┴──────┐  ┌───────┴──────┐  ┌──────────────┐
    │ geolocation │  │   products   │  │   reviews    │
    └─────────────┘  └───────┬──────┘  └──────────────┘
                             │
                     ┌───────┴──────┐  ┌──────────────┐
                     │   sellers    │  │  category    │
                     └─────────────-┘  │ translation  │
                                       └──────────────┘
```

**Key design note:** `customer_id` is generated per order. `customer_unique_id` is the stable per-person identifier. Always use `customer_unique_id` for retention analysis.

---

## Tech Stack

| Layer | Tool | Purpose |
|-------|------|---------|
| Database | PostgreSQL 15 | Core data storage and analytics |
| DB Client | SQL Workbench/J | Schema management, query execution |
| Language | Python 3.11 | ETL, automation, exports |
| Libraries | psycopg2, SQLAlchemy, pandas, openpyxl | DB connection, transformation, Excel |
| Reporting | Microsoft Excel | Pivot tables, KPI charts |
| Visualization | Tableau Desktop + Tableau Public | Interactive dashboards |
| Version Control | Git + GitHub | Project history and portfolio |

---

## How to Run This Project

### Prerequisites
- PostgreSQL 15+ installed and running
- Python 3.9+ with pip
- SQL Workbench/J (or DBeaver/pgAdmin)
- Tableau Desktop (or Tableau Public)

### Step 1 — Clone the repository
```bash
git clone https://github.com/acaca675/olist-ecommerce-analysis.git
cd olist-ecommerce-analysis
```

### Step 2 — Install Python dependencies
```bash
pip install -r requirements.txt
```

### Step 3 — Configure credentials
```bash
cp config/.env.template config/.env
# Edit config/.env with your PostgreSQL password
```

### Step 4 — Create the database (in psql or SQL Workbench)
```sql
CREATE DATABASE olist_db;
```

### Step 5 — Run the schema script
```sql
-- In SQL Workbench, connect to olist_db and run:
\i sql/schema/01_create_schema.sql
```

### Step 6 — Import CSV data
```bash
# Download CSVs from Kaggle and place in data/raw/
# Then run:
python python/connection/01_db_setup.py
```

### Step 7 — Run analytics queries
Open `sql/analytics/03_analytics_queries.sql` in SQL Workbench and execute each block.

### Step 8 — Create Tableau views
```sql
\i sql/views/04_tableau_views.sql
```

### Step 9 — Export to Excel
```bash
python python/exports/02_export_to_excel.py
```

### Step 10 — Connect Tableau
In Tableau Desktop: **Connect → To a Server → PostgreSQL**
- Server: `localhost` | Port: `5432` | Database: `olist_db` | Schema: `olist`
- Connect to views: `v_orders_full`, `v_seller_metrics`, `v_category_performance`, `v_geo_orders`

---

## SQL Highlights

### Advanced techniques demonstrated:
- **Window Functions**: `RANK()`, `NTILE()`, `LAG()`, rolling averages with `ROWS BETWEEN`
- **CTEs**: Multi-step analytical pipelines with named intermediate results
- **CASE Statements**: Business segmentation logic (RFM, seller quadrants, delivery buckets)
- **Date Math**: `EXTRACT(EPOCH FROM ...)` for precise delivery delay calculation
- **Conditional Aggregation**: `SUM(CASE WHEN ... THEN 1 ELSE 0 END)` for KPI ratios
- **Correlated Analysis**: Review score vs. delivery delay across 100k orders

---

## Tableau Dashboard Structure

| Page | Key Charts |
|------|-----------|
| Executive Summary | Monthly GMV line, top categories bar, Brazil choropleth map, KPI cards |
| Delivery Performance | On-time % by state, delay heatmap (seller → customer state), trend line |
| Customer Satisfaction | Score histogram, score by category, delay vs. score scatter |
| Seller Intelligence | Revenue vs. quality quadrant, top 20 ranked table, state distribution |

---

## Business Recommendations

1. **Prioritize delivery SLA enforcement** — late deliveries directly cause 1-star reviews; a 10% improvement in on-time rate could raise average platform score by ~0.2 points
2. **Launch a seller quality program** — the "High Revenue, Low Quality" quadrant sellers are platform liabilities; pair high GMV with minimum review score thresholds
3. **Investigate freight subsidy for remote states** — customers in AM, RR, AP bear 3× the freight burden of SP customers; a regional logistics partnership could unlock market growth
4. **Build a retention strategy** — with only 3.1% repeat purchase rate, even modest improvements compound significantly at 100k order scale

---

## Data Source

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) — released under CC BY-NC-SA 4.0. All company/partner references anonymised using Game of Thrones house names.

---

## Author

**Nabilla Salsabilla** | [LinkedIn](https://www.linkedin.com/in/nabillasalsa/) 

*This project was built as part of a data analytics portfolio. All analysis reflects the publicly available dataset; findings are exploratory, not prescriptive.*
