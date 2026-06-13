#!/usr/bin/env python3
"""Front-half parity check (Python reference) for KK-MasterVP, BTCUSD M3.

Fast-iteration cross-check BEFORE wiring the C++ parity harness: reproduce the
MT5 parity_*.csv computation layer (master VP + regime + indicators) from the
imported clean ticks and diff against the tester reference. Confirms bid-bar
convention, window semantics, and Wilder indicator convergence.

MT5 facts (from KK-MasterVP source + baseline.set):
  - M3 candles built on BID; tick_volume == per-bar tick count.
  - master VP: ComputeVP(len=150, bins=30, va=70, startShift=1) over bars [T..T-149].
  - bar-feed VP (InpVpFeedMode=0): hlc3 -> bin, weight = tick_volume.
  - regime read at shift 1 (bar T): iATR(14), iMA EMA(24/194,close), iADX(14).
  - barTimeUTC = server time (InpBrokerGMTOffset=0) == our tick ts.
"""
import sys
import numpy as np
import pandas as pd
import duckdb

REF = ("/Users/tokyotechies/Workspace/KEM/kenkem/Tester/Agent-127.0.0.1-3000/"
       "MQL5/Files/KK-MasterVP/parity_BTCUSD-Exnes-0406_PERIOD_M3.csv")
# tick source: "clean" or "raw" (cli arg 1). raw == exact MT5-exported ticks.
SRC = sys.argv[1] if len(sys.argv) > 1 else "clean"
TICKS = f"data/processed/ticks_btcusd_2026{'_clean' if SRC == 'clean' else ''}.parquet"

MASTER_LEN, BINS, VA_PCT = 150, 30, 70.0
ATR_LEN, ADX_LEN, EMA_F, EMA_S = 14, 14, 24, 194
ADX_TREND_MIN, DI_SPREAD_MIN, EMA_SEP_ATR = 22.0, 6.0, 0.25  # see InputParams.mqh


def build_bid_m3_bars():
    """Bid-based M3 OHLC + tick count for all of 2026 up to the ref window end."""
    con = duckdb.connect()
    df = con.sql(f"""
        with b as (
          select
            time_bucket(interval '3 minutes', ts) as bts,
            arg_min(bid, ts) as open,
            max(bid)         as high,
            min(bid)         as low,
            arg_max(bid, ts) as close,
            count(*)         as tick_count
          from '{TICKS}'
          where ts < timestamp '2026-04-10'
          group by 1
        )
        select bts, open, high, low, close, tick_count
        from b order by bts
    """).df()
    return df


def wilder_rma(x, n):
    """Wilder smoothing (alpha = 1/n), seeded with the simple mean of the first n."""
    x = np.asarray(x, float)
    out = np.full(len(x), np.nan)
    if len(x) < n:
        return out
    seed = x[:n].mean()
    out[n - 1] = seed
    prev = seed
    for i in range(n, len(x)):
        prev = (prev * (n - 1) + x[i]) / n
        out[i] = prev
    return out


def compute_atr(high, low, close, n):
    h, l, c = map(lambda a: np.asarray(a, float), (high, low, close))
    prev_c = np.roll(c, 1)
    prev_c[0] = c[0]
    tr = np.maximum(h - l, np.maximum(np.abs(h - prev_c), np.abs(l - prev_c)))
    tr[0] = h[0] - l[0]
    return wilder_rma(tr, n)


def ema_on_buffer(x, n, start):
    """MT5 ExponentialMAOnBuffer: k=2/(n+1), seeded with x[start] at index start."""
    x = np.asarray(x, float)
    out = np.full(len(x), np.nan)
    k = 2.0 / (n + 1.0)
    prev = x[start]
    out[start] = prev
    for i in range(start + 1, len(x)):
        prev = x[i] * k + prev * (1 - k)
        out[i] = prev
    return out


def compute_adx(high, low, close, n):
    """MT5 built-in iADX (NOT Wilder iADXWilder): per-bar PD/ND = 100*DM/TR,
    then EMA(2/(n+1)) smoothing of +DI/-DI and of DX. Mirrors MT5 ADX.mq5."""
    h, l, c = map(lambda a: np.asarray(a, float), (high, low, close))
    N = len(h)
    pd = np.zeros(N); nd = np.zeros(N)
    for i in range(1, N):
        plus_dm = h[i] - h[i - 1]
        minus_dm = l[i - 1] - l[i]
        if plus_dm < 0: plus_dm = 0.0
        if minus_dm < 0: minus_dm = 0.0
        if plus_dm > minus_dm: minus_dm = 0.0
        elif minus_dm > plus_dm: plus_dm = 0.0
        else: plus_dm = minus_dm = 0.0
        tr = max(h[i], c[i - 1]) - min(l[i], c[i - 1])
        if tr != 0.0:
            pd[i] = 100.0 * plus_dm / tr
            nd[i] = 100.0 * minus_dm / tr
    plus_di = ema_on_buffer(pd, n, 1)
    minus_di = ema_on_buffer(nd, n, 1)
    with np.errstate(divide="ignore", invalid="ignore"):
        s = plus_di + minus_di
        dx = np.where(s != 0.0, 100.0 * np.abs(plus_di - minus_di) / s, 0.0)
    dx = np.nan_to_num(dx, nan=0.0)
    adx = ema_on_buffer(dx, n, 1)
    return adx, plus_di, minus_di


def ema(x, n):
    x = np.asarray(x, float)
    out = np.full(len(x), np.nan)
    if len(x) < n:
        return out
    k = 2.0 / (n + 1.0)
    seed = x[:n].mean()
    out[n - 1] = seed
    prev = seed
    for i in range(n, len(x)):
        prev = x[i] * k + prev * (1 - k)
        out[i] = prev
    return out


def build_va_from_hist(hist, lo, step):
    total = hist.sum()
    poc_idx = int(np.argmax(hist))
    target = total * (VA_PCT * 0.01)
    acc = hist[poc_idx]
    lo_idx = hi_idx = poc_idx
    bins = len(hist)
    while acc < target and (lo_idx > 0 or hi_idx < bins - 1):
        next_l = hist[lo_idx - 1] if lo_idx > 0 else -1.0
        next_h = hist[hi_idx + 1] if hi_idx < bins - 1 else -1.0
        if next_h >= next_l:
            hi_idx += 1; acc += hist[hi_idx]
        else:
            lo_idx -= 1; acc += hist[lo_idx]
    poc = lo + (poc_idx + 0.5) * step
    vah = lo + (hi_idx + 1.0) * step
    val = lo + lo_idx * step
    return poc, vah, val


def compute_vp(window):
    """window: DataFrame of 150 bars (oldest..newest). Bar-feed hlc3 VP."""
    lo = window["low"].min()
    hi = window["high"].max()
    step = (hi - lo) / BINS
    if step <= 0:
        return None
    hlc3 = (window["high"] + window["low"] + window["close"]) / 3.0
    bi = np.clip(np.floor((hlc3 - lo) / step).astype(int), 0, BINS - 1)
    hist = np.zeros(BINS)
    np.add.at(hist, bi, window["tick_count"].to_numpy(float))
    poc, vah, val = build_va_from_hist(hist, lo, step)
    return dict(poc=poc, vah=vah, val=val, hi=hi, lo=lo)


def main():
    bars = build_bid_m3_bars()
    print(f"[bars] {len(bars)} bid M3 bars, {bars.bts.min()} .. {bars.bts.max()}")

    h, l, c = bars["high"].to_numpy(), bars["low"].to_numpy(), bars["close"].to_numpy()
    atr = compute_atr(h, l, c, ATR_LEN)
    adx, plus_di, minus_di = compute_adx(h, l, c, ADX_LEN)
    ema_f = ema(c, EMA_F)
    ema_s = ema(c, EMA_S)

    bts_to_idx = {t: i for i, t in enumerate(bars["bts"])}

    ref = pd.read_csv(REF)
    ref["t"] = pd.to_datetime(ref["barTimeUTC"], format="%Y.%m.%d %H:%M")

    rows = []
    for _, r in ref.iterrows():
        t = r["t"].to_pydatetime().replace(tzinfo=None)
        t64 = pd.Timestamp(t)
        if t64 not in bts_to_idx:
            rows.append(dict(t=t, miss=True))
            continue
        i = bts_to_idx[t64]
        if i < MASTER_LEN - 1:
            rows.append(dict(t=t, miss=True))
            continue
        win = bars.iloc[i - MASTER_LEN + 1: i + 1]
        vp = compute_vp(win)
        trend = (adx[i] > ADX_TREND_MIN and abs(plus_di[i] - minus_di[i]) > DI_SPREAD_MIN
                 and abs(ema_f[i] - ema_s[i]) > EMA_SEP_ATR * atr[i])
        rows.append(dict(
            t=t, miss=False,
            mpoc=vp["poc"], mvah=vp["vah"], mval=vp["val"],
            atr1=atr[i], adx=adx[i], plus=plus_di[i], minus=minus_di[i],
            trend=int(trend),
            r_mpoc=r["mpoc"], r_mvah=r["mvah"], r_mval=r["mval"],
            r_atr1=r["atr1"], r_adx=r["adx"], r_plus=r["plus"], r_minus=r["minus"],
            r_trend=int(r["trend"]),
        ))
    out = pd.DataFrame(rows)
    matched = out[~out["miss"]].copy()
    print(f"[match] {len(matched)}/{len(out)} ref rows aligned to a bar")

    def stat(col, rcol):
        d = (matched[col] - matched[rcol]).abs()
        return d.max(), d.mean()

    for col, rcol in [("mpoc", "r_mpoc"), ("mvah", "r_mvah"), ("mval", "r_mval"),
                      ("atr1", "r_atr1"), ("adx", "r_adx"),
                      ("plus", "r_plus"), ("minus", "r_minus")]:
        mx, mn = stat(col, rcol)
        print(f"  {col:6s}  max|Δ|={mx:12.4f}   mean|Δ|={mn:10.4f}")
    trend_match = (matched["trend"] == matched["r_trend"]).mean()
    print(f"  trend  agree={trend_match*100:.1f}%")

    # show worst master-VP rows
    matched["dvah"] = (matched["mvah"] - matched["r_mvah"]).abs()
    worst = matched.nlargest(5, "dvah")[["t", "mvah", "r_mvah", "mval", "r_mval", "mpoc", "r_mpoc"]]
    print("\n[worst mvah rows]\n", worst.to_string(index=False))
    print("\n[first 3 matched]\n",
          matched[["t", "mvah", "r_mvah", "atr1", "r_atr1", "adx", "r_adx",
                   "plus", "r_plus", "minus", "r_minus", "trend", "r_trend"]].head(3).to_string(index=False))


if __name__ == "__main__":
    main()
