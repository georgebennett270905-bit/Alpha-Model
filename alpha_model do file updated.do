/* 

   ALPHA MODEL — FULL STATA PIPELINE
   Dependent variable: Next-month stock return
   
   Steps:
     1.  Import & label
     2.  Clean & deduplicate
     3.  Create variables & signals
     4.  Winsorise outliers
     5.  Set panel structure
     6.  Summary statistics
     7.  Correlation matrix
     8.  Pooled OLS
     9.  Fixed effects (stock + time)
     10. Fama-MacBeth cross-sectional regressions

*/

global filepath "C:/Users/georg/OneDrive - The University of Nottingham/Alpha Model Work/alpha_data_v2.xlsx"
global outpath  "C:/Users/georg/OneDrive - The University of Nottingham/Alpha Model Work/"        // where logs/results go

cap log close
log using "${outpath}alpha_model_log.txt", text replace


/* 
   1 — IMPORT
*/
   
import excel "C:\Users\georg\OneDrive - The University of Nottingham\Alpha Model Work\alpha_data_v2.xlsx", ///
    sheet("Raw_Data") cellrange(A3) firstrow clear

describe
import excel "${filepath}", ///
    sheet("Raw_Data") cellrange(A3) firstrow clear

/* Rename columns to clean names */

rename dateYYYYMM        date
rename tickerStockcode   ticker
rename priceAdjclose     price
rename pe_ratioPEapp~x   pe_ratio
rename pb_ratioPBapp~x   pb_ratio
rename div_yieldDivY~a   div_yield
rename momentum121mo     momentum
rename beta_12m12mor~g   beta_12m
rename rsi_14RSI14mo~d   rsi_14
rename mktcap_bnMktc~n   mktcap_bn
rename sectorGICSsec~r   sector

/* Label variables */

label var date       "Year-Month (YYYY-MM)"
label var ticker     "Stock ticker"
label var price      "Adjusted closing price (USD)"
label var pe_ratio   "Price-to-earnings ratio (approx.)"
label var pb_ratio   "Price-to-book ratio (approx.)"
label var div_yield  "Dividend yield (% p.a.)"
label var momentum   "12-1 month momentum (%)"
label var beta_12m   "Rolling 12-month beta vs S&P 500"
label var rsi_14     "RSI-14 at month end"
label var mktcap_bn  "Market capitalisation (USD bn)"
label var sector     "GICS sector"

di "Raw rows imported: `=_N'"


/* 
   2 — CLEAN & DEDUPLICATE
*/

/* Convert numeric columns (imported as string if mixed) */
destring pe_ratio pb_ratio div_yield momentum ///
         beta_12m rsi_14 mktcap_bn price, replace force

/* Drop rows missing price — nothing can be calculated */
drop if missing(price)

/* Create a proper monthly date variable Stata can use */
gen modate = monthly(date, "YM")
format modate %tm
label var modate "Monthly date (Stata format)"

/* Deduplicate — keep one row per stock per month */
duplicates drop ticker modate, force

/* Encode sector as numeric for fixed effects */
encode sector, gen(sector_id)

di "Rows after cleaning: `=_N'"

/*=
	3 — CREATE VARIABLES & SIGNALS
*/
   
/* Sort panel before any time-series operations */
sort ticker modate

/* ── Monthly return (from price)  */
by ticker: gen ret = (price / price[_n-1]) - 1
label var ret "Monthly stock return"

/* ── DEPENDENT VARIABLE: next-month return */
by ticker: gen ret_fwd = ret[_n+1]
label var ret_fwd "Forward 1-month return (dependent variable)"

/* ── Value signals */

gen ep = 1 / pe_ratio if pe_ratio > 0        
// earnings yield
gen bm = 1 / pb_ratio if pb_ratio > 0       
// book-to-market

label var ep "Earnings yield (1/PE)"
label var bm "Book-to-market (1/PB)"

/* ── Size signal */

gen log_mktcap = log(mktcap_bn) if mktcap_bn > 0
label var log_mktcap "Log market cap (size)"

/* ── RSI signals */

gen rsi_centred  = rsi_14 - 50               

// centred for regression

gen overbought   = (rsi_14 > 70) if !missing(rsi_14)
gen oversold     = (rsi_14 < 30) if !missing(rsi_14)

label var rsi_centred "RSI-14 centred at 50"
label var overbought  "RSI > 70 (overbought dummy)"
label var oversold    "RSI < 30 (oversold dummy)"

/* ── Low-beta dummy */

gen low_beta = (beta_12m < 1) if !missing(beta_12m)
label var low_beta "Beta < 1 dummy (low-beta anomaly)"

replace div_yield = 0 if missing(div_yield)


/*
  4 — WINSORISE OUTLIERS
*/

cap ssc install winsor2, replace

winsor2 ret_fwd momentum ep bm beta_12m rsi_centred div_yield log_mktcap, ///
        cuts(1 99) suffix(_w)

label var ret_fwd_w   "Forward return (winsorised)"
label var momentum_w  "Momentum 12-1 (winsorised)"
label var ep_w        "Earnings yield (winsorised)"
label var bm_w        "Book-to-market (winsorised)"
label var beta_12m_w  "Beta 12m (winsorised)"
label var rsi_centred_w "RSI centred (winsorised)"
label var div_yield_w "Dividend yield (winsorised)"
label var log_mktcap_w "Log mktcap (winsorised)"


/* 
  5 — SET PANEL STRUCTURE
*/
/* Create numeric stock ID */

egen stock_id = group(ticker)
label var stock_id "Numeric stock identifier"

xtset stock_id modate
di "Panel set: stock_id x modate"


/* 
   6 — SUMMARY STATISTICS
*/

di _newline "========== SUMMARY STATISTICS =========="
estpost summarize ret_fwd_w momentum_w ep_w bm_w ///
                  div_yield_w beta_12m_w rsi_centred_w log_mktcap_w, detail

/* Count coverage by stock */

di _newline "========== MONTHS PER STOCK =========="
bysort ticker: gen nobs = _N
tabstat nobs, by(ticker) stat(mean) nototal


/*
   7 — CORRELATION MATRIX
*/

di _newline "========== CORRELATIONS =========="
pwcorr ret_fwd_w momentum_w ep_w bm_w ///
       div_yield_w beta_12m_w rsi_centred_w log_mktcap_w, ///
       star(0.05)


/* 
   8 — POOLED OLS  (baseline)
*/

di _newline "========== POOLED OLS =========="
reg ret_fwd_w momentum_w ep_w bm_w ///
              div_yield_w beta_12m_w rsi_centred_w log_mktcap_w, ///
    robust
estimates store pooled_ols


/* 
   9 — FIXED EFFECTS
*/

/* 9a. Stock fixed effects only */

di _newline "========== FIXED EFFECTS (stock) =========="
xtreg ret_fwd_w momentum_w ep_w bm_w ///
                div_yield_w beta_12m_w rsi_centred_w log_mktcap_w, ///
      fe robust
estimates store fe_stock

/* 9b. Time fixed effects only */

di _newline "========== FIXED EFFECTS (time) =========="
areg ret_fwd_w momentum_w ep_w bm_w ///
               div_yield_w beta_12m_w rsi_centred_w log_mktcap_w, ///
     absorb(modate) robust
estimates store fe_time

/* 9c. Two-way fixed effects: stock + time (preferred spec) */

di _newline "========== TWO-WAY FIXED EFFECTS (stock + time) =========="
cap ssc install reghdfe, replace
cap ssc install ftools,  replace

reghdfe ret_fwd_w momentum_w ep_w bm_w ///
                  div_yield_w beta_12m_w rsi_centred_w log_mktcap_w, ///
        absorb(stock_id modate) vce(robust)
estimates store fe_twoway


/*
   10 — FAMA-MacBETH  (standard in asset pricing)
   Runs a cross-sectional regression each month,
   then averages the coefficients — Newey-West SEs
   Requires: ssc install asreg
*/

di _newline "========== FAMA-MacBETH =========="
cap ssc install asreg, replace

asreg ret_fwd_w momentum_w ep_w bm_w ///
                div_yield_w beta_12m_w rsi_centred_w log_mktcap_w, ///
      fmb newey(3)
	  
/* newey(3) = Newey-West with 3 lags to correct for autocorrelation */


/* 
   RESULTS TABLE
*/
cap ssc install estout, replace

esttab pooled_ols fe_stock fe_time fe_twoway ///
    using "${outpath}alpha_results.csv", ///
    replace csv ///
    title("Alpha Model — Regression Results") ///
    mtitles("Pooled OLS" "Stock FE" "Time FE" "Two-way FE") ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    scalars(N r2 r2_a) ///
    note("Dependent variable: forward 1-month return (winsorised). Robust SEs.")

di _newline "✅ Results saved to: ${outpath}alpha_results.csv"


/* 
   
   momentum_w  — positive & significant = momentum effect
                 (past winners keep winning)
   
   ep_w        — positive & significant = value effect
                 (cheap stocks by earnings outperform)
   
   bm_w        — positive & significant = value effect
                 (Fama-French HML factor)
   
   div_yield_w — positive = income/quality premium
   
   beta_12m_w  — negative = low-beta anomaly
                 (lower risk stocks outperform on risk-adj basis)
   
   rsi_centred_w — negative = mean reversion
                   (overbought stocks underperform next month)
   
   log_mktcap_w — negative = size effect
                  (smaller stocks outperform — Fama-French SMB)
   
   ★ Use Two-way FE or Fama-MacBeth as your main specification.
     Pooled OLS is just a baseline check.
    */

/* 
   ROBUSTNESS CHECKS — append to bottom of alpha_model.do
   1. Sub-period analysis (Pre-COVID / COVID / Post-COVID)
   2. Sector analysis (Tech / Financials / Other)
  */


/* 
   ROBUSTNESS 1 — SUB-PERIOD ANALYSIS
   Period 1: Jan 2020 – Feb 2020  (Pre-COVID)
   Period 2: Mar 2020 – Dec 2022  (COVID & recovery)
   Period 3: Jan 2023 – Mar 2026  (Post-COVID / rate cycle)
    */
	
di _newline "========== ROBUSTNESS: SUB-PERIOD ANALYSIS =========="

/* Create period labels */
gen period = .
replace period = 1 if modate >= tm(2020m1)  & modate <= tm(2020m2)
replace period = 2 if modate >= tm(2020m3)  & modate <= tm(2022m12)
replace period = 3 if modate >= tm(2023m1)  & modate <= tm(2026m3)

label define periodlbl 1 "Pre-COVID" 2 "COVID & Recovery" 3 "Post-COVID"
label values period periodlbl
label var period "Sub-period indicator"

/* Check period coverage */
di _newline "Observations per period:"
tab period

/* Period 1: Pre-COVID (Jan–Feb 2020) 

   Note: only 2 months so treat as context only, not main result */
   
di _newline "--- Period 1: Pre-COVID (Jan-Feb 2020) ---"
reghdfe ret_fwd_w momentum_w ep_w bm_w ///
                  div_yield_w beta_12m_w rsi_centred_w log_mktcap_w ///
                  if period == 1, ///
        absorb(stock_id modate) vce(robust)
estimates store rob_precovid

/* Period 2: COVID & Recovery (Mar 2020 – Dec 2022)  */

di _newline "--- Period 2: COVID & Recovery (Mar 2020 - Dec 2022) ---"
reghdfe ret_fwd_w momentum_w ep_w bm_w ///
                  div_yield_w beta_12m_w rsi_centred_w log_mktcap_w ///
                  if period == 2, ///
        absorb(stock_id modate) vce(robust)
estimates store rob_covid

/* Period 3: Post-COVID (Jan 2023 – Mar 2026) */

di _newline "--- Period 3: Post-COVID (Jan 2023 - Mar 2026) ---"
reghdfe ret_fwd_w momentum_w ep_w bm_w ///
                  div_yield_w beta_12m_w rsi_centred_w log_mktcap_w ///
                  if period == 3, ///
        absorb(stock_id modate) vce(robust)
estimates store rob_postcovid

/* Export sub-period results */
esttab rob_precovid rob_covid rob_postcovid ///
    using "${outpath}robustness_subperiod.csv", ///
    replace csv ///
    title("Robustness — Sub-period Analysis (Two-way FE)") ///
    mtitles("Pre-COVID" "COVID & Recovery" "Post-COVID") ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    scalars(N r2 r2_a) ///
    note("Dependent variable: forward 1-month return (winsorised). Robust SEs. Two-way FE.")

di "✅ Sub-period results saved to: ${outpath}robustness_subperiod.csv"


/*=
   ROBUSTNESS 2 — SECTOR ANALYSIS
   Group 1: Technology
   Group 2: Financials
   Group 3: Other (all remaining sectors)
 = */
 
di _newline "========== ROBUSTNESS: SECTOR ANALYSIS =========="

/* Create sector group variable */

gen sector_group = 3                                    
replace sector_group = 1 if sector == "Technology"
replace sector_group = 2 if sector == "Financials"

label define sectorlbl 1 "Technology" 2 "Financials" 3 "Other"
label values sector_group sectorlbl
label var sector_group "Broad sector grouping"

/* Check sector coverage */
di _newline "Observations per sector group:"
tab sector_group

/* ── Sector 1: Technology */

di _newline "--- Sector: Technology ---"
reghdfe ret_fwd_w momentum_w ep_w bm_w ///
                  div_yield_w beta_12m_w rsi_centred_w log_mktcap_w ///
                  if sector_group == 1, ///
        absorb(stock_id modate) vce(robust)
estimates store rob_tech

/* ── Sector 2: Financials */

di _newline "--- Sector: Financials ---"
reghdfe ret_fwd_w momentum_w ep_w bm_w ///
                  div_yield_w beta_12m_w rsi_centred_w log_mktcap_w ///
                  if sector_group == 2, ///
        absorb(stock_id modate) vce(robust)
estimates store rob_fin

/* ── Sector 3: Other */

di _newline "--- Sector: Other ---"
reghdfe ret_fwd_w momentum_w ep_w bm_w ///
                  div_yield_w beta_12m_w rsi_centred_w log_mktcap_w ///
                  if sector_group == 3, ///
        absorb(stock_id modate) vce(robust)
estimates store rob_other

/* Export sector results */
esttab rob_tech rob_fin rob_other ///
    using "${outpath}robustness_sector.csv", ///
    replace csv ///
    title("Robustness — Sector Analysis (Two-way FE)") ///
    mtitles("Technology" "Financials" "Other") ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    scalars(N r2 r2_a) ///
    note("Dependent variable: forward 1-month return (winsorised). Robust SEs. Two-way FE.")

di "✅ Sector results saved to: ${outpath}robustness_sector.csv"


/*=
   ROBUSTNESS 3 — FULL COMPARISON TABLE
   Main result vs all robustness checks side by side 
= */

di _newline "========== FULL COMPARISON TABLE =========="

esttab fe_twoway rob_covid rob_postcovid rob_tech rob_fin rob_other ///
    using "${outpath}robustness_full.csv", ///
    replace csv ///
    title("Full Robustness Comparison — Two-way FE across all subsamples") ///
    mtitles("Full Sample" "COVID Period" "Post-COVID" "Tech" "Financials" "Other") ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    scalars(N r2 r2_a) ///
    note("Dependent variable: forward 1-month return (winsorised). Robust SEs. Two-way FE throughout.")

di "✅ Full comparison saved to: ${outpath}robustness_full.csv"


/*=
   MACRO CONTROLS MODEL
= */

* Import the merged file
import excel "alpha_macro_data.xlsx", ///
    sheet("Merged_Panel") cellrange(A3) firstrow clear

* ── Rename all 19 columns 

rename YYYYMM          date
rename Stockcode        ticker
rename Adjclose         price
rename PEapprox         pe_ratio
rename PBapprox         pb_ratio
rename DivYieldpa       div_yield
rename Momentum121mo    momentum
rename Beta12morolling  beta_12m
rename RSI14moend       rsi_14
rename Mktcapbn         mktcap_bn
rename GICSsector       sector
rename FedFundsRate     fed_funds
rename FedFundsChgpp    fed_funds_chg
rename YieldCurve10Y2Y  yield_curve
rename YieldCurveChgpp  yield_curve_chg
rename BreakevenInfl    breakeven_inf
rename BreakevenChgpp   breakeven_chg
rename CreditSpdOAS     credit_spread
rename CreditSpdChgpp   credit_spd_chg

* ── Destring numeric columns 

destring price pe_ratio pb_ratio div_yield momentum beta_12m rsi_14 mktcap_bn ///
         fed_funds fed_funds_chg yield_curve yield_curve_chg ///
         breakeven_inf breakeven_chg credit_spread credit_spd_chg, replace force

* ── Create Stata date variable 

gen modate = monthly(date, "YM")
format modate %tm

* ── Re-run variable construction 

sort ticker modate
by ticker: gen ret     = (price / price[_n-1]) - 1
by ticker: gen ret_fwd = ret[_n+1]
gen ep          = 1/pe_ratio  if pe_ratio > 0
gen bm          = 1/pb_ratio  if pb_ratio > 0
gen log_mktcap  = log(mktcap_bn) if mktcap_bn > 0
gen rsi_centred = rsi_14 - 50
replace div_yield = 0 if missing(div_yield)
egen stock_id   = group(ticker)
xtset stock_id modate

* ── Winsorise 

winsor2 ret_fwd ep bm momentum beta_12m rsi_centred div_yield log_mktcap ///
        fed_funds_chg yield_curve_chg breakeven_chg credit_spd_chg, ///
        cuts(1 99) suffix(_w)

* ── Macro only 

reg ret_fwd_w fed_funds_chg_w yield_curve_chg_w ///
              breakeven_chg_w credit_spd_chg_w, robust
estimates store macro_only

* ── Signals + macro (no FE) 

reg ret_fwd_w momentum_w ep_w bm_w div_yield_w ///
              beta_12m_w rsi_centred_w log_mktcap_w ///
              fed_funds_chg_w yield_curve_chg_w ///
              breakeven_chg_w credit_spd_chg_w, robust
estimates store signals_macro

* ── Stock FE + macro controls (preferred spec) 

reghdfe ret_fwd_w momentum_w ep_w bm_w div_yield_w ///
                  beta_12m_w rsi_centred_w log_mktcap_w ///
                  fed_funds_chg_w yield_curve_chg_w ///
                  breakeven_chg_w credit_spd_chg_w, ///
        absorb(stock_id) vce(robust)
estimates store stock_fe_macro

* ── Export results 

esttab macro_only signals_macro stock_fe_macro ///
    using "${outpath}macro_results.csv", ///
    replace csv ///
    title("Macro Controls — Regression Results") ///
    mtitles("Macro only" "Signals + Macro" "Stock FE + Macro") ///
    b(4) se(4) star(* 0.10 ** 0.05 *** 0.01) ///
    scalars(N r2 r2_a) ///
    note("Dependent variable: forward 1-month return (winsorised). Robust SEs.")
	
log close
