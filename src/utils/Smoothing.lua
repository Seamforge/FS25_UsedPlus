--[[
    FS25_UsedPlus - Value Smoothing Utility

    Provides exponential moving average (EMA) for reducing UI jitter.
    Pattern from: MoreRealistic_FS25 & realismAddon_gearbox smoothing

    v2.8.0: Initial implementation for tire wear, marketplace offers, credit scores
]]

Smoothing = {}

--[[
    Smooth a value using exponential moving average
    @param newValue - New raw value
    @param oldValue - Previous smoothed value (can be nil for first update)
    @param factor - Smoothing factor (0.0-1.0)
                    0.1 = very smooth (slow response)
                    0.3 = balanced
                    0.5 = responsive (minimal smoothing)
    @return smoothedValue
]]
function Smoothing.ema(newValue, oldValue, factor)
    if oldValue == nil then
        return newValue  -- First update, no history
    end
    return (newValue * factor) + (oldValue * (1 - factor))
end

--[[
    Smooth a percentage value with bounds clamping
    @param newPercent - New percentage (0-100)
    @param oldPercent - Previous smoothed percentage
    @param factor - Smoothing factor (0.1-0.5)
    @return smoothedPercent (clamped 0-100)
]]
function Smoothing.emaPercent(newPercent, oldPercent, factor)
    local smoothed = Smoothing.ema(newPercent, oldPercent, factor)
    return math.max(0, math.min(100, smoothed))
end

--[[
    Smooth a condition value (0.0-1.0 scale)
    @param newCondition - New condition (0-1)
    @param oldCondition - Previous smoothed condition
    @param factor - Smoothing factor (0.1-0.5)
    @return smoothedCondition (clamped 0-1)
]]
function Smoothing.emaCondition(newCondition, oldCondition, factor)
    local smoothed = Smoothing.ema(newCondition, oldCondition, factor)
    return math.max(0, math.min(1, smoothed))
end

--[[
    Smooth a price/money value
    @param newPrice - New price value
    @param oldPrice - Previous smoothed price
    @param factor - Smoothing factor (0.1-0.5)
    @return smoothedPrice (clamped >= 0)
]]
function Smoothing.emaPrice(newPrice, oldPrice, factor)
    local smoothed = Smoothing.ema(newPrice, oldPrice, factor)
    return math.max(0, smoothed)
end

--[[
    Smooth an integer value (e.g., credit score)
    @param newInt - New integer value
    @param oldInt - Previous smoothed integer
    @param factor - Smoothing factor (0.1-0.5)
    @return smoothedInt (rounded to nearest integer)
]]
function Smoothing.emaInt(newInt, oldInt, factor)
    local smoothed = Smoothing.ema(newInt, oldInt, factor)
    return math.floor(smoothed + 0.5)  -- Round to nearest
end

UsedPlus.logInfo("Smoothing utility loaded")
