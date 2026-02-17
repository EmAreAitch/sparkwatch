# SparkWatch

Student engagement analytics with ML-powered dropout prediction.

> **[Live Demo →](https://sparkwatch.onrender.com)**

SparkWatch monitors student activity across cohorts, calculates weighted engagement scores, and uses a Random Forest classifier to identify students at risk of dropping out — enabling early intervention.

<!-- Add screenshots here once the app is deployed and styled:
![Platform Dashboard](docs/screenshots/platform_overview.png)
![Student Detail](docs/screenshots/student_detail.png)
-->

---

## Features

- **Platform Dashboard** — KPIs, weekly engagement trends, risk distribution, activity breakdown
- **Cohort Analytics** — Instructor performance rankings, cohort size-engagement correlation, completion projections
- **Student Overview** — Engagement distribution, momentum tracking, risk-engagement quadrant, filtered lists (at-risk, high performers, inactive)
- **Student Detail** — Individual engagement timeline, prediction breakdown with per-feature explainability, actionable recommendations
- **Dropout Prediction** — Random Forest classifier with 50K synthetic training samples, 5% label noise, and feature scaling
- **Skeleton Loading** — Every dashboard widget loads asynchronously with animated placeholders
- **Keyset Pagination** — Efficient cursor-based pagination for large student lists

---

## Architecture

SparkWatch uses a **Sim-to-Real** architecture to prevent data drift between synthetic environments:

```
StudentSimulator (shared behavioral model)
    │
    ├── db/seeds.rb
    │     └── Generates realistic student activity across 6 cohorts
    │
    └── lib/tasks/ml.rake
          └── Generates 50K labeled training samples
                    ↓
              RandomForest + StandardScaler
                    ↓
              Prediction.generate_for(students)
                    ↓
              Dashboard Services (widget-based, memoized)
                    ↓
              Stimulus Controllers + Chart.js
```

The same `StudentSimulator` drives both seeding and training. This guarantees the ML model understands the exact behavioral patterns present in the application data — a common pitfall in demo projects where seed scripts and training scripts drift apart.



---

## Tech Stack

| Layer      | Technology                                            |
|------------|-------------------------------------------------------|
| Backend    | Ruby 4.0.1 · Rails 8.1 · PostgreSQL                  |
| Frontend   | Hotwire (Turbo + Stimulus) · Tailwind CSS · Chart.js · Grid.js |
| ML         | Rumale (Random Forest) · Numo::NArray                 |
| Background | Solid Queue (async mode embedded in Puma)             |
| API        | js_from_routes (auto-generated typed JS API clients)  |
| CI         | GitHub Actions (Brakeman, bundler-audit, RuboCop, tests) |
| Deploy     | Docker · Render                                       |

---

## Setup

> This repo uses **Git LFS** for the trained ML model file (`lib/ml/dropout_model.marshal`). Make sure Git LFS is installed.

```bash
# Clone (Git LFS will pull the model automatically)
git clone https://github.com/EmAreAitch/sparkwatch.git
cd sparkwatch

# Install dependencies
bundle install

# Create database
bin/rails db:prepare

# Seed data (requires the trained model to exist)
bin/rails db:seed

# Start the dev server
bin/dev
```

Visit `http://localhost:3000` to see the Platform Overview dashboard.

### Retraining the model (optional)

The trained model is included via Git LFS, so retraining is not required. If you want to retrain:

```bash
bin/rails ml:train
```

This generates 50K synthetic samples using `StudentSimulator`, trains a Random Forest classifier (150 estimators, 80/20 split), and serializes the model to `lib/ml/dropout_model.marshal`.

---

## Project Structure

```
app/
├── models/
│   ├── engagement_score.rb    # Weighted scoring engine, momentum, distribution
│   ├── prediction.rb          # ML inference, batch prediction, risk classification
│   ├── activity.rb            # Activity tracking, lateral joins
│   ├── student.rb             # Query centralization, search
│   └── cohort.rb              # Tier classification
├── services/dashboard/        # 7 widget-based service objects
├── controllers/dashboard/     # Lean controllers (data delegation only)
├── javascript/
│   ├── controllers/           # 13 Stimulus controllers
│   └── api/                   # Auto-generated typed API routes
└── views/dashboard/           # ERB templates with skeleton loading

lib/
├── tasks/
│   └── ml.rake                # Training pipeline (rake ml:train)
└── ml/
    └── dropout_model.marshal  # Serialized model (Git LFS)
```

---

## License

This project is for demonstration purposes.
