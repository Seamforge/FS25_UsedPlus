--[[
    FS25_UsedPlus - Depreciation Calculations Utility

    Handles used vehicle pricing and depreciation
    Pattern from: BuyUsedEquipment "Probabilistic Depreciation System"
    Reference: FS25_ADVANCED_PATTERNS.md - Depreciation patterns
    Reference: FS25_UsedPlus.md lines 1830-1883 (generation tables)

    Functionality:
    - Generation-based depreciation (Recent/Mid-age/Old)
    - Random age, damage, wear, hours within generation ranges
    - Integration with game's built-in depreciation system
    - Realistic used vehicle pricing

    Generations:
    1. Recent (0-3 years): 12-25% discount, low damage/wear
    2. Mid-age (4-7 years): 25-45% discount, medium damage/wear
    3. Old (8-15 years): 45-75% discount, high damage/wear
]]

DepreciationCalculations = {}

--[[
    Generation definitions from BuyUsedEquipment pattern
    Each generation defines ranges for age, discount, hours, damage, wear
]]
DepreciationCalculations.GENERATIONS = {
    {  -- Generation 1: Recent (like new)
        name = "Recent",
        maxAge = 3,                    -- 0-3 years old
        discount = { 0.12, 0.25 },     -- 12% to 25% off
        hours = { 100, 800 },          -- Hours per year
        damage = { 0.02, 0.08 },       -- 2% to 8% paint damage
        wear = { 0.01, 0.10 },         -- 1% to 10% wear
    },
    {  -- Generation 2: Mid-age (used)
        name = "Mid-age",
        maxAge = 7,                    -- 4-7 years old
        discount = { 0.25, 0.45 },     -- 25% to 45% off
        hours = { 200, 1200 },         -- Hours per year
        damage = { 0.08, 0.20 },       -- 8% to 20% paint damage
        wear = { 0.10, 0.25 },         -- 10% to 25% wear
    },
    {  -- Generation 3: Old (well-used)
        name = "Old",
        maxAge = 15,                   -- 8-15 years old
        discount = { 0.45, 0.75 },     -- 45% to 75% off
        hours = { 500, 2500 },         -- Hours per year
        damage = { 0.20, 0.50 },       -- 20% to 50% paint damage
        wear = { 0.25, 0.60 },         -- 25% to 60% wear
    }
}

--[[
    Quality tier definitions - player's desired condition preference
    Lower quality = lower price but more damage/wear to repair
    Higher quality = higher price but less repair needed
    Array order: 1=Any, 2=Poor, 3=Fair, 4=Good, 5=Excellent
    Must match UsedSearchDialog.QUALITY_TIERS order!

    BALANCE NOTE (v1.2): Original discounts were too aggressive (50-75% off),
    making used vehicles always better than new. Rebalanced to 15-45% off
    to keep used competitive but not game-breaking. Combined with reliability
    consequences, used vehicles are now a meaningful tradeoff.
]]
--[[
    Quality tier definitions with RANGES (v1.4.0 - ECONOMICS.md compliance)
    Each tier uses min/max ranges for price, damage, and wear to ensure:
    1. No overlap between tiers (worst Excellent < best Poor after repairs)
    2. Realistic variance within each tier
    3. Clear price/condition tradeoffs for player decision-making

    Order: 1=Any, 2=Poor, 3=Fair, 4=Good, 5=Excellent
    Must match UsedSearchDialog.QUALITY_TIERS order!
]]
DepreciationCalculations.QUALITY_TIERS = {
    {  -- Any Condition: Catch-all with widest variance
        name = "Any Condition",
        priceRangeMin = 0.30,            -- 30% of new (70% off)
        priceRangeMax = 0.50,            -- 50% of new (50% off)
        damageRange = { 0.35, 0.60 },    -- 35-60% damage
        wearRange = { 0.40, 0.65 },      -- 40-65% wear
        description = "Wildcard - high variance in quality and price"
    },
    {  -- Poor Condition: Fixer-upper - highest repair costs
        name = "Poor Condition",
        priceRangeMin = 0.22,            -- 22% of new (78% off)
        priceRangeMax = 0.38,            -- 38% of new (62% off)
        damageRange = { 0.55, 0.80 },    -- 55-80% damage
        wearRange = { 0.60, 0.85 },      -- 60-85% wear
        description = "Bargain bin - extensive repairs needed"
    },
    {  -- Fair Condition: Middle ground
        name = "Fair Condition",
        priceRangeMin = 0.50,            -- 50% of new (50% off)
        priceRangeMax = 0.68,            -- 68% of new (32% off)
        damageRange = { 0.18, 0.35 },    -- 18-35% damage
        wearRange = { 0.22, 0.40 },      -- 22-40% wear
        description = "Moderate wear - some repairs likely"
    },
    {  -- Good Condition: Well maintained
        name = "Good Condition",
        priceRangeMin = 0.68,            -- 68% of new (32% off)
        priceRangeMax = 0.80,            -- 80% of new (20% off)
        damageRange = { 0.06, 0.18 },    -- 6-18% damage
        wearRange = { 0.08, 0.22 },      -- 8-22% wear
        description = "Well maintained - minimal repairs"
    },
    {  -- Excellent Condition: Like new
        name = "Excellent Condition",
        priceRangeMin = 0.80,            -- 80% of new (20% off)
        priceRangeMax = 0.94,            -- 94% of new (6% off)
        damageRange = { 0.00, 0.06 },    -- 0-6% damage
        wearRange = { 0.00, 0.08 },      -- 0-8% wear
        description = "Like new - ready to work immediately"
    }
}

--[[
    Search tier condition modifiers
    Higher tier = better chance of finding good condition vehicles
    Local (1): Worse condition, more old vehicles
    Regional (2): Normal condition distribution
    National (3): Better condition, more recent vehicles
]]
DepreciationCalculations.TIER_MODIFIERS = {
    [1] = {  -- Local: Worse quality
        generationWeights = { 0.20, 0.50, 0.30 },  -- 20% recent, 50% mid-age, 30% old
        damageMultiplier = 1.3,   -- 30% more damage
        wearMultiplier = 1.3,     -- 30% more wear
    },
    [2] = {  -- Regional: Normal quality
        generationWeights = { 0.40, 0.40, 0.20 },  -- 40% recent, 40% mid-age, 20% old
        damageMultiplier = 1.0,   -- Normal damage
        wearMultiplier = 1.0,     -- Normal wear
    },
    [3] = {  -- National: Better quality
        generationWeights = { 0.55, 0.35, 0.10 },  -- 55% recent, 35% mid-age, 10% old
        damageMultiplier = 0.7,   -- 30% less damage
        wearMultiplier = 0.7,     -- 30% less wear
    }
}

--[[
    Select random generation
    Can be weighted or forced for specific searches
    searchLevel affects generation distribution
    Returns: generation index (1, 2, or 3)
]]
function DepreciationCalculations.selectGeneration(preferredGeneration, searchLevel)
    if preferredGeneration ~= nil then
        return preferredGeneration
    end

    -- Get tier modifier (default to regional/normal if not specified)
    local tierMod = DepreciationCalculations.TIER_MODIFIERS[searchLevel] or DepreciationCalculations.TIER_MODIFIERS[2]
    local weights = tierMod.generationWeights

    -- Random generation selection based on tier weights
    math.random()  -- Dry run for better randomness
    local roll = math.random()

    if roll <= weights[1] then
        return 1  -- Recent
    elseif roll <= (weights[1] + weights[2]) then
        return 2  -- Mid-age
    else
        return 3  -- Old
    end
end

--[[
    Generate random value within a range
    Uses linear interpolation
]]
function DepreciationCalculations.getRandomValue(range)
    math.random()  -- Dry run
    return range[1] + math.random() * (range[2] - range[1])
end

--[[
    Generate complete used vehicle parameters
    searchLevel affects generation distribution (age)
    qualityLevel determines damage/wear ranges (player's condition preference)
    Returns table with: age, damage, wear, hours, discount, generation, qualityLevel
]]
function DepreciationCalculations.generateUsedVehicleParams(preferredGeneration, searchLevel, qualityLevel)
    local generationIndex = DepreciationCalculations.selectGeneration(preferredGeneration, searchLevel)
    local generation = DepreciationCalculations.GENERATIONS[generationIndex]

    -- Get tier modifier for search level adjustments (affects generation probability)
    local tierMod = DepreciationCalculations.TIER_MODIFIERS[searchLevel] or DepreciationCalculations.TIER_MODIFIERS[2]

    -- Get quality tier for damage/wear ranges (player's condition preference)
    local qualityLevel = qualityLevel or 1  -- Default to "Any Condition"
    local qualityTier = DepreciationCalculations.QUALITY_TIERS[qualityLevel] or DepreciationCalculations.QUALITY_TIERS[1]

    -- Random values within generation ranges
    local age = math.random(1, generation.maxAge)
    local hoursPerYear = DepreciationCalculations.getRandomValue(generation.hours)
    local discount = DepreciationCalculations.getRandomValue(generation.discount)

    -- Generate damage/wear based on QUALITY TIER (player's preference)
    -- Then apply SEARCH TIER modifier (local finds worse condition, national finds better)
    local baseDamage = DepreciationCalculations.getRandomValue(qualityTier.damageRange)
    local baseWear = DepreciationCalculations.getRandomValue(qualityTier.wearRange)

    local damage = math.min(0.95, math.max(0.01, baseDamage * tierMod.damageMultiplier))
    local wear = math.min(0.95, math.max(0.01, baseWear * tierMod.wearMultiplier))

    -- Calculate total operating hours
    local operatingHours = age * hoursPerYear

    UsedPlus.logDebug(string.format("Generated vehicle params: quality=%s, searchTier=%d",
        qualityTier.name, searchLevel))
    UsedPlus.logDebug(string.format("  Damage: %.1f%%, Wear: %.1f%%, Age: %d years, Hours: %d",
        damage * 100, wear * 100, age, operatingHours))

    return {
        age = age,
        damage = damage,
        wear = wear,
        operatingHours = operatingHours,
        discount = discount,
        generation = generationIndex,
        generationName = generation.name,
        searchLevel = searchLevel,
        qualityLevel = qualityLevel,
        qualityName = qualityTier.name
    }
end

--[[
    Calculate used vehicle price using quality tier multiplier
    The game's calculateSellPrice deducts repair costs which makes poor condition
    vehicles nearly worthless. Instead, we use quality-based pricing that reflects
    what buyers would actually pay for a fixer-upper.
    Returns: usedPrice, repairCost, repaintCost
]]
function DepreciationCalculations.calculateUsedPrice(storeItem, params)
    -- Get base price with configurations
    local defaultPrice = StoreItemUtil.getDefaultPrice(storeItem, {})

    -- Calculate repair and repaint costs using game formulas (for display)
    local repairPrice = 0
    local repaintPrice = 0
    if Wearable and Wearable.calculateRepairPrice then
        repairPrice = Wearable.calculateRepairPrice(defaultPrice, params.damage)
    end
    if Wearable and Wearable.calculateRepaintPrice then
        repaintPrice = Wearable.calculateRepaintPrice(defaultPrice, params.wear)
    end

    -- Get quality tier for price multiplier (v1.4.0: now uses ranges)
    local qualityTier = DepreciationCalculations.QUALITY_TIERS[params.qualityLevel] or DepreciationCalculations.QUALITY_TIERS[1]

    -- Select price within tier's range (random variance within bounds)
    local priceRangeMin = qualityTier.priceRangeMin or 0.30
    local priceRangeMax = qualityTier.priceRangeMax or 0.50
    local qualityMultiplier = priceRangeMin + (math.random() * (priceRangeMax - priceRangeMin))

    -- Age-based depreciation (vehicles lose value over time)
    -- BALANCE NOTE (v1.2): Reduced from 5%/year (max 50%) to 3%/year (max 25%)
    -- This prevents age from stacking too aggressively with quality discounts
    local ageDepreciation = math.min(0.25, (params.age or 0) * 0.03)
    local ageMultiplier = 1.0 - ageDepreciation

    -- Calculate used price:
    -- Base price * quality multiplier (from range) * age multiplier
    -- This gives reasonable prices with realistic variance within each tier
    local usedPrice = defaultPrice * qualityMultiplier * ageMultiplier

    -- Ensure minimum price of 5% of base (vehicles are never completely worthless)
    local minPrice = defaultPrice * 0.05
    usedPrice = math.max(usedPrice, minPrice)

    UsedPlus.logDebug(string.format("Price calc: base=$%.0f, quality=%.0f%%, age=%.0f%%, final=$%.0f",
        defaultPrice, qualityMultiplier * 100, ageMultiplier * 100, usedPrice))

    return math.floor(usedPrice), math.floor(repairPrice), math.floor(repaintPrice)
end


--[[
    Get condition rating text for display
    Based on average of damage and wear
]]
function DepreciationCalculations.getConditionRating(damage, wear)
    local condition = (damage + wear) / 2

    if condition <= 0.10 then
        return g_i18n:getText("usedplus_condition_excellent"), 1
    elseif condition <= 0.25 then
        return g_i18n:getText("usedplus_condition_good"), 2
    elseif condition <= 0.45 then
        return g_i18n:getText("usedplus_condition_fair"), 3
    else
        return g_i18n:getText("usedplus_condition_poor"), 4
    end
end

--[[
    Format vehicle age for display
]]
function DepreciationCalculations.formatAge(ageYears)
    if ageYears == 1 then
        return g_i18n:getText("usedplus_age_oneYear")
    else
        return string.format(g_i18n:getText("usedplus_age_years"), ageYears)
    end
end

--[[
    Format operating hours for display
]]
function DepreciationCalculations.formatOperatingHours(hours)
    return string.format(g_i18n:getText("usedplus_hours"), math.floor(hours))
end

UsedPlus.logInfo("DepreciationCalculations utility loaded")
