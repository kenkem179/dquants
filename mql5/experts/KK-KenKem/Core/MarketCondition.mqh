//+------------------------------------------------------------------+
//| MarketCondition.mqh - Market Regime Analysis (Singleton)         |
//| Phase 1.3: OOP Foundation - Market Context (Stub)               |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, KenKem"
#property strict

#ifndef MARKETCONDITION_MQH
#define MARKETCONDITION_MQH

#include "GlobalState.mqh"

//+------------------------------------------------------------------+
//| Market Regime Types                                             |
//+------------------------------------------------------------------+
enum MARKET_REGIME {
    REGIME_TRENDING_STRONG,     // High volatility + strong trend
    REGIME_TRENDING_WEAK,       // Moderate trend
    REGIME_RANGING,             // Low ADX, choppy
    REGIME_VOLATILE_RANGING,    // High volatility but no clear trend
    REGIME_UNKNOWN
};

//+------------------------------------------------------------------+
//| MarketCondition: Singleton for market regime analysis           |
//| Provides context for adaptive parameter adjustments             |
//+------------------------------------------------------------------+
class MarketCondition {
private:
    static MarketCondition* s_instance;
    
    // Market state cache
    datetime m_lastUpdateTime;
    MARKET_REGIME m_currentRegime;
    double m_volatilityPercentile;  // 0-100
    
    // Private constructor for singleton
    MarketCondition() {
        m_lastUpdateTime = 0;
        m_currentRegime = REGIME_UNKNOWN;
        m_volatilityPercentile = 50.0;
        if(showDebug) Print("[MarketCondition] Singleton initialized");
    }
    
public:
    //--------------------------------------------------------------------
    // Singleton access
    //--------------------------------------------------------------------
    static MarketCondition* GetInstance() {
        if(s_instance == NULL) {
            s_instance = new MarketCondition();
        }
        return s_instance;
    }
    
    static void Destroy() {
        if(s_instance != NULL) {
            delete s_instance;
            s_instance = NULL;
        }
    }
    
    //--------------------------------------------------------------------
    // Update market state (call once per bar)
    //--------------------------------------------------------------------
    void Update() {
        // Stub - will calculate regime and volatility in Phase 3
        m_lastUpdateTime = TimeCurrent();
    }
    
    //--------------------------------------------------------------------
    // Getters (used by EntryBase adaptive logic)
    //--------------------------------------------------------------------
    MARKET_REGIME GetCurrentRegime() {
        return m_currentRegime;
    }
    
    double GetVolatilityPercentile() {
        // Returns 0-100 (percentile of recent ATR)
        return m_volatilityPercentile;
    }
    
    bool IsHighVolatility() {
        return m_volatilityPercentile > 80.0;
    }
    
    bool IsLowVolatility() {
        return m_volatilityPercentile < 20.0;
    }
};

// Static instance initialization
static MarketCondition* MarketCondition::s_instance = NULL;

#endif // MARKETCONDITION_MQH
