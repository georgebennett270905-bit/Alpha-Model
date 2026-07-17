# Alpha-Model
# Equity Alpha Model — Stock Return Predictors in the S&P 500

**Author:** George | University of Nottingham | July 2026

A cross-sectional equity alpha model built from scratch to identify firm-level and macroeconomic predictors of one-month forward stock returns. Data collected via Python (Google Colab), analysis conducted in Stata 18.

---

## Overview

This project constructs and evaluates an alpha model using a panel of **30 large-cap S&P 500 stocks** observed monthly from **January 2020 to March 2026** (75 months, ~2,250 observations).

Seven firm-level signals are tested against forward one-month returns using progressively demanding econometric specifications — pooled OLS through to two-way fixed effects and Fama-MacBeth regressions. A supplementary macro-factor analysis incorporates yield curve and credit spread variables.

---

## Repository Structure

```
├── collect_alpha_data.py       # Python script — automated data collection via yfinance
├── alpha_model_do_file.do      # Stata do file — full pipeline from import to robustness checks
├── alpha_model_paper.docx      # Full research paper with tables, references, and methodology
└── README.md
```

---

## Signals Tested

| Signal | Construction | Expected sign |
|---|---|---|
| Earnings yield (EP) | 1 / PE ratio | + (value premium) |
| Book-to-market (BM) | 1 / PB ratio | + (value premium) |
| Momentum (12-1) | Cumulative return, months t-12 to t-2 | + (Jegadeesh-Titman) |
| RSI-14 | Relative Strength Index centred at 50 | − (mean reversion) |
| Log market cap | Log of market cap in $bn | − (size effect) |
| Beta (12m rolling) | Market beta vs S&P 500 | − (low-beta anomaly) |
| Dividend yield | Annual yield, missing set to zero | + (quality/income) |

All signals winsorised at the 1st and 99th percentiles.

---

## Methodology

- **Panel:** 30 stocks × 75 months, January 2020–March 2026
- **Dependent variable:** Forward one-month stock return (winsorised)
- **Specifications:** Pooled OLS → Stock FE → Time FE → Two-way FE → Fama-MacBeth
- **Macro extension:** Yield curve change, credit spread change, fed funds change, breakeven inflation change
- **Robustness:** Sub-period analysis (Pre-COVID / COVID & Recovery / Post-COVID) and sector analysis (Technology / Financials / Other)
- **Software:** Python (yfinance, pandas) for data collection; Stata 18 (reghdfe, asreg, winsor2, estout) for analysis

---

## Key Findings

### Main specification (two-way fixed effects, N = 2,220, R² = 34.8%)

| Signal | Coefficient | Significance | Interpretation |
|---|---|---|---|
| Log market cap | −0.0553 | *** | Smaller stocks outperform — consistent with Fama-French SMB |
| RSI-14 (centred) | +0.0005 | *** | Momentum persistence in large-cap equities over 1-month horizon |
| Earnings yield | −0.3718 | *** | Negative within-firm effect — consistent with value trap dynamics |
| Momentum (12-1) | ≈ 0 | n.s. | Not significant in this sample or time period |
| Beta, BM, Div yield | — | n.s. | Insignificant across all specifications |

### Macro factors (COVID & recovery period, N = 1,020)

| Variable | Coefficient | Significance |
|---|---|---|
| Yield curve change (10Y−2Y) | +0.105 | *** |
| Credit spread change (OAS) | −0.184 | *** |
| Fed funds change | +0.024 | n.s. |
| Breakeven inflation change | −0.006 | n.s. |

A steepening yield curve and tightening credit spreads both independently predict positive equity returns, consistent with the macroeconomic literature.

### Robustness
- The **size effect** (log market cap) is negative and significant in both sub-periods with adequate sample size (COVID and post-COVID) and in the 'Other' sector group
- The **RSI signal** is positive and significant in both the COVID and post-COVID periods
- The **earnings yield** sign flips between Fama-MacBeth (+0.224, p < 0.01) and fixed effects (−0.372, p < 0.01) — reflecting a well-documented distinction between cross-sectional value premia and within-firm time-series dynamics

---

## Notable Results

The earnings yield sign flip is the most analytically interesting finding. Fama-MacBeth identifies a positive cross-sectional value premium (cheap stocks outperform expensive peers in the same month), while fixed effects identify a negative within-firm time-series effect (when a stock gets cheaper relative to its own history, it tends to underperform). This mirrors findings in the asset pricing literature and is consistent with value trap dynamics among large-cap growth stocks post-2020.

**Macro factors dominate the COVID period.** 
Credit spread changes alone explain more of the cross-sectional return variation than firm-level signals during the COVID shock, consistent with a risk-off channel where credit market stress leads equity returns.

---

## Limitations

- Cross-section of 30 stocks is small relative to academic asset pricing standards — limits statistical power and generalisability
- US large-cap only — size effect identified here differs from the classic Fama-French small-vs-large specification
- P/E approximated as price / trailing EPS (EPS refreshes quarterly, not monthly) — a limitation of the data collection approach
- In-sample evaluation — no out-of-sample backtest conducted in this version
- 75-month panel constrains the number of Fama-MacBeth coefficient observations

---

## Data Collection

Data collected automatically using the `collect_alpha_data.py` script via the `yfinance` library. Requires Python 3 and the following libraries:

```bash
pip install yfinance openpyxl pandas
```

Run the script:

```bash
python collect_alpha_data.py
```

Outputs `alpha_data.xlsx` with adjusted monthly prices, approximate P/E (price / trailing EPS), and market cap for all 30 stocks over the sample period.

---

## Stata Pipeline

The full Stata pipeline (`alpha_model_do_file.do`) covers:

1. Import and variable renaming
2. Destring, deduplication, date conversion
3. Signal construction (returns, EP, BM, log mktcap, RSI, beta, momentum)
4. Winsorisation (winsor2, cuts at 1/99)
5. Panel declaration (xtset)
6. Summary statistics and correlation matrix
7. Pooled OLS, stock FE, time FE, two-way FE (reghdfe)
8. Fama-MacBeth regression (asreg with Newey-West, 3 lags)
9. Macro factor extension
10. Sub-period and sector robustness checks
11. Results export (esttab → CSV)

---

## References

Banz (1981) · Fama & French (1992, 1993, 1998) · Jegadeesh & Titman (1993) · Carhart (1997) · Fama & MacBeth (1973) · Chen, Roll & Ross (1986) · Harvey (1989) · Campbell & Taksler (2003) · Petersen (2009) · Daniel & Moskowitz (2016) · Gilchrist & Zakrajšek (2012) · Wilder (1978)

---

*Built as preparatory work for dissertation-level research. Feedback welcome.*
