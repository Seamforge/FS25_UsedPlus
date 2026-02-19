--[[
    FS25_UsedPlus - Fault Tracer Grid Engine

    Pure logic module for generating and managing the Minesweeper-inspired
    diagnostic grid used by the Fault Tracer minigame.

    Responsibilities:
    - Generate grid based on vehicle component reliability
    - Place faults with deducibility validation
    - Calculate adjacency numbers (classic Minesweeper)
    - Assign fault types (Corroded/Cracked/Seized)
    - Calculate gauge colors (worst-severity-of-neighbors)
    - Flood-fill cascade for zero cells
    - Pre-reveal safe cells for easier difficulties

    v2.12.0 - Fault Tracer Minigame
]]

FaultTracerGrid = {}

-- Cell states
FaultTracerGrid.STATE_HIDDEN = "hidden"
FaultTracerGrid.STATE_REVEALED = "revealed"
FaultTracerGrid.STATE_FLAGGED = "flagged"

-- Fault types (in order of severity)
FaultTracerGrid.FAULT_CORRODED = "corroded"
FaultTracerGrid.FAULT_CRACKED = "cracked"
FaultTracerGrid.FAULT_SEIZED = "seized"

-- Gauge colors
FaultTracerGrid.GAUGE_GREEN = "green"
FaultTracerGrid.GAUGE_AMBER = "amber"
FaultTracerGrid.GAUGE_RED = "red"

-- Severity order for gauge calculation
FaultTracerGrid.SEVERITY = {
    [FaultTracerGrid.FAULT_CORRODED] = 1,
    [FaultTracerGrid.FAULT_CRACKED] = 2,
    [FaultTracerGrid.FAULT_SEIZED] = 3,
}

--[[
    Get grid parameters based on component reliability.
    Lower reliability = larger grid, more faults, harder types.

    @param reliability number 0.0-1.0
    @return table {rows, cols, numFaults, preRevealed, faultTypeWeights}
]]
function FaultTracerGrid.getGridParams(reliability)
    local params = {}

    if reliability >= 0.7 then
        -- Easy: small grid, few faults, simple types
        params.rows = 3
        params.cols = 3
        params.numFaults = math.random(1, 2)
        params.preRevealed = math.random(2, 3)
        params.faultTypeWeights = {
            [FaultTracerGrid.FAULT_CORRODED] = 1.0,
            [FaultTracerGrid.FAULT_CRACKED] = 0.0,
            [FaultTracerGrid.FAULT_SEIZED] = 0.0,
        }
        params.baseGain = 0.10
        params.ceilingGain = 0.005
    elseif reliability >= 0.5 then
        -- Medium: moderate grid, mixed faults
        params.rows = 3
        params.cols = 4
        params.numFaults = math.random(2, 3)
        params.preRevealed = math.random(1, 2)
        params.faultTypeWeights = {
            [FaultTracerGrid.FAULT_CORRODED] = 0.5,
            [FaultTracerGrid.FAULT_CRACKED] = 0.5,
            [FaultTracerGrid.FAULT_SEIZED] = 0.0,
        }
        params.baseGain = 0.15
        params.ceilingGain = 0.010
    elseif reliability >= 0.3 then
        -- Hard: larger grid, more faults, all types
        params.rows = 4
        params.cols = 4
        params.numFaults = math.random(3, 4)
        params.preRevealed = math.random(0, 1)
        params.faultTypeWeights = {
            [FaultTracerGrid.FAULT_CORRODED] = 0.3,
            [FaultTracerGrid.FAULT_CRACKED] = 0.4,
            [FaultTracerGrid.FAULT_SEIZED] = 0.3,
        }
        params.baseGain = 0.18
        params.ceilingGain = 0.015
    else
        -- Expert: max grid, many faults, weighted toward seized
        params.rows = 4
        params.cols = 5
        params.numFaults = math.random(4, 5)
        params.preRevealed = 0
        params.faultTypeWeights = {
            [FaultTracerGrid.FAULT_CORRODED] = 0.2,
            [FaultTracerGrid.FAULT_CRACKED] = 0.3,
            [FaultTracerGrid.FAULT_SEIZED] = 0.5,
        }
        params.baseGain = 0.23
        params.ceilingGain = 0.020
    end

    return params
end

--[[
    Generate a complete grid for a given component and reliability.

    @param component string "engine"|"electrical"|"hydraulic"
    @param reliability number 0.0-1.0
    @return table Complete grid state
]]
function FaultTracerGrid.generate(component, reliability)
    local params = FaultTracerGrid.getGridParams(reliability)

    -- Create empty grid
    local grid = {
        rows = params.rows,
        cols = params.cols,
        component = component,
        reliability = reliability,
        params = params,
        cells = {},
        faultPositions = {},
        faultTypes = {},
        totalFaults = params.numFaults,
        faultsFound = 0,
        probeCount = 0,
        faultHits = 0,
        hintsUsed = 0,
        quickScanUsed = false,
    }

    -- Initialize cells
    for r = 1, params.rows do
        grid.cells[r] = {}
        for c = 1, params.cols do
            grid.cells[r][c] = {
                isFault = false,
                faultType = nil,
                number = 0,
                gaugeColor = FaultTracerGrid.GAUGE_GREEN,
                state = FaultTracerGrid.STATE_HIDDEN,
                previousState = nil,
                flaggedType = nil,
            }
        end
    end

    -- Place faults with deducibility validation
    grid.faultPositions = FaultTracerGrid.placeFaults(params.rows, params.cols, params.numFaults)

    -- Mark fault cells
    for _, pos in ipairs(grid.faultPositions) do
        grid.cells[pos.row][pos.col].isFault = true
    end

    -- Assign fault types
    grid.faultTypes = FaultTracerGrid.assignFaultTypes(grid.faultPositions, params.faultTypeWeights)
    for _, pos in ipairs(grid.faultPositions) do
        grid.cells[pos.row][pos.col].faultType = grid.faultTypes[pos.row .. "_" .. pos.col]
    end

    -- Calculate adjacency numbers
    FaultTracerGrid.calculateNumbers(grid)

    -- Calculate gauge colors for all cells
    FaultTracerGrid.calculateGaugeColors(grid)

    -- Pre-reveal safe cells
    if params.preRevealed > 0 then
        FaultTracerGrid.preRevealCells(grid, params.preRevealed)
    end

    return grid
end

--[[
    Place faults on the grid with deducibility validation.
    Each fault must have at least one non-fault neighbor (so numbers can hint at it).
    Retries placement up to 100 times to find a valid configuration.

    @param rows number
    @param cols number
    @param numFaults number
    @return table Array of {row, col} positions
]]
function FaultTracerGrid.placeFaults(rows, cols, numFaults)
    local maxAttempts = 100

    for _ = 1, maxAttempts do
        local positions = {}
        local occupied = {}

        for i = 1, numFaults do
            local placed = false
            for _ = 1, 50 do
                local r = math.random(1, rows)
                local c = math.random(1, cols)
                local key = r .. "_" .. c

                if not occupied[key] then
                    occupied[key] = true
                    table.insert(positions, { row = r, col = c })
                    placed = true
                    break
                end
            end

            if not placed then
                break
            end
        end

        if #positions == numFaults then
            -- Validate deducibility: each fault must have at least one non-fault neighbor
            local valid = true
            for _, pos in ipairs(positions) do
                local hasNonFaultNeighbor = false
                for dr = -1, 1 do
                    for dc = -1, 1 do
                        if dr ~= 0 or dc ~= 0 then
                            local nr = pos.row + dr
                            local nc = pos.col + dc
                            if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols then
                                local nkey = nr .. "_" .. nc
                                if not occupied[nkey] then
                                    hasNonFaultNeighbor = true
                                end
                            end
                        end
                    end
                end
                if not hasNonFaultNeighbor then
                    valid = false
                    break
                end
            end

            if valid then
                return positions
            end
        end
    end

    -- Fallback: place faults with deducibility validation via brute-force retry
    -- On small grids (max 4x5 with 5 faults), this converges quickly
    for _ = 1, 200 do
        local fallback = {}
        local used = {}
        local allSpots = {}

        for r = 1, rows do
            for c = 1, cols do
                table.insert(allSpots, { row = r, col = c })
            end
        end

        -- Shuffle and pick
        for i = 1, math.min(numFaults, #allSpots) do
            local idx = math.random(1, #allSpots)
            local spot = allSpots[idx]
            used[spot.row .. "_" .. spot.col] = true
            table.insert(fallback, spot)
            table.remove(allSpots, idx)
        end

        if #fallback == numFaults then
            -- Validate deducibility
            local valid = true
            for _, pos in ipairs(fallback) do
                local hasNonFaultNeighbor = false
                for dr = -1, 1 do
                    for dc = -1, 1 do
                        if dr ~= 0 or dc ~= 0 then
                            local nr = pos.row + dr
                            local nc = pos.col + dc
                            if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols then
                                if not used[nr .. "_" .. nc] then
                                    hasNonFaultNeighbor = true
                                end
                            end
                        end
                    end
                end
                if not hasNonFaultNeighbor then
                    valid = false
                    break
                end
            end

            if valid then
                return fallback
            end
        end
    end

    -- Ultimate fallback: place first fault at (1,1) — always has non-fault neighbors on any grid >= 2x2
    local lastResort = {}
    for i = 1, math.min(numFaults, rows) do
        table.insert(lastResort, { row = i, col = 1 })
    end
    return lastResort
end

--[[
    Calculate adjacency numbers for all non-fault cells.
    Each cell's number = count of adjacent fault cells (8-directional).

    @param grid table The grid to update in-place
]]
function FaultTracerGrid.calculateNumbers(grid)
    for r = 1, grid.rows do
        for c = 1, grid.cols do
            if not grid.cells[r][c].isFault then
                local count = 0
                for dr = -1, 1 do
                    for dc = -1, 1 do
                        if dr ~= 0 or dc ~= 0 then
                            local nr = r + dr
                            local nc = c + dc
                            if nr >= 1 and nr <= grid.rows and nc >= 1 and nc <= grid.cols then
                                if grid.cells[nr][nc].isFault then
                                    count = count + 1
                                end
                            end
                        end
                    end
                end
                grid.cells[r][c].number = count
            end
        end
    end
end

--[[
    Assign fault types based on difficulty-weighted probabilities.

    @param faultPositions table Array of {row, col}
    @param weights table {corroded=float, cracked=float, seized=float}
    @return table Map of "row_col" -> faultType string
]]
function FaultTracerGrid.assignFaultTypes(faultPositions, weights)
    local types = {}

    -- Build weighted selection array
    local pool = {}
    if weights[FaultTracerGrid.FAULT_CORRODED] > 0 then
        table.insert(pool, { type = FaultTracerGrid.FAULT_CORRODED, weight = weights[FaultTracerGrid.FAULT_CORRODED] })
    end
    if weights[FaultTracerGrid.FAULT_CRACKED] > 0 then
        table.insert(pool, { type = FaultTracerGrid.FAULT_CRACKED, weight = weights[FaultTracerGrid.FAULT_CRACKED] })
    end
    if weights[FaultTracerGrid.FAULT_SEIZED] > 0 then
        table.insert(pool, { type = FaultTracerGrid.FAULT_SEIZED, weight = weights[FaultTracerGrid.FAULT_SEIZED] })
    end

    -- If no valid weights, default to corroded
    if #pool == 0 then
        for _, pos in ipairs(faultPositions) do
            types[pos.row .. "_" .. pos.col] = FaultTracerGrid.FAULT_CORRODED
        end
        return types
    end

    -- Normalize weights
    local totalWeight = 0
    for _, entry in ipairs(pool) do
        totalWeight = totalWeight + entry.weight
    end

    for _, pos in ipairs(faultPositions) do
        local roll = math.random() * totalWeight
        local cumulative = 0
        local chosen = pool[1].type

        for _, entry in ipairs(pool) do
            cumulative = cumulative + entry.weight
            if roll <= cumulative then
                chosen = entry.type
                break
            end
        end

        types[pos.row .. "_" .. pos.col] = chosen
    end

    return types
end

--[[
    Calculate gauge colors for all cells.
    Gauge color = worst severity of adjacent faults.
    Green = no adjacent faults (or only corroded if not directly adjacent)
    Amber = at least one adjacent cracked fault
    Red = at least one adjacent seized fault

    @param grid table The grid to update in-place
]]
function FaultTracerGrid.calculateGaugeColors(grid)
    for r = 1, grid.rows do
        for c = 1, grid.cols do
            if not grid.cells[r][c].isFault then
                local worstSeverity = 0

                for dr = -1, 1 do
                    for dc = -1, 1 do
                        if dr ~= 0 or dc ~= 0 then
                            local nr = r + dr
                            local nc = c + dc
                            if nr >= 1 and nr <= grid.rows and nc >= 1 and nc <= grid.cols then
                                local neighbor = grid.cells[nr][nc]
                                if neighbor.isFault and neighbor.faultType ~= nil then
                                    local severity = FaultTracerGrid.SEVERITY[neighbor.faultType] or 0
                                    if severity > worstSeverity then
                                        worstSeverity = severity
                                    end
                                end
                            end
                        end
                    end
                end

                if worstSeverity >= 3 then
                    grid.cells[r][c].gaugeColor = FaultTracerGrid.GAUGE_RED
                elseif worstSeverity >= 2 then
                    grid.cells[r][c].gaugeColor = FaultTracerGrid.GAUGE_AMBER
                else
                    grid.cells[r][c].gaugeColor = FaultTracerGrid.GAUGE_GREEN
                end
            end
        end
    end
end

--[[
    Flood-fill cascade from a zero cell.
    Reveals all connected zero cells and their border (non-zero, non-fault) neighbors.

    @param grid table
    @param startRow number
    @param startCol number
    @return table Array of {row, col} cells that were revealed
]]
function FaultTracerGrid.cascadeReveal(grid, startRow, startCol)
    local revealed = {}
    local queue = {}
    local visited = {}

    table.insert(queue, { row = startRow, col = startCol })
    visited[startRow .. "_" .. startCol] = true

    while #queue > 0 do
        local current = table.remove(queue, 1)
        local r = current.row
        local c = current.col
        local cell = grid.cells[r][c]

        -- Reveal this cell
        if cell.state == FaultTracerGrid.STATE_HIDDEN then
            cell.state = FaultTracerGrid.STATE_REVEALED
            table.insert(revealed, { row = r, col = c })
        end

        -- If this is a zero cell, expand to neighbors
        if cell.number == 0 and not cell.isFault then
            for dr = -1, 1 do
                for dc = -1, 1 do
                    if dr ~= 0 or dc ~= 0 then
                        local nr = r + dr
                        local nc = c + dc
                        local nkey = nr .. "_" .. nc

                        if nr >= 1 and nr <= grid.rows and nc >= 1 and nc <= grid.cols then
                            if not visited[nkey] then
                                visited[nkey] = true
                                local neighbor = grid.cells[nr][nc]
                                if not neighbor.isFault then
                                    table.insert(queue, { row = nr, col = nc })
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    return revealed
end

--[[
    Pre-reveal safe cells for easier difficulties.
    Picks zero-cells first (to trigger cascade), then low-number cells.

    @param grid table
    @param count number How many cells to pre-reveal
    @return table Array of {row, col} cells revealed (may be more than count due to cascade)
]]
function FaultTracerGrid.preRevealCells(grid, count)
    local allRevealed = {}

    -- Collect safe candidates sorted by number (zeroes first for cascade)
    local candidates = {}
    for r = 1, grid.rows do
        for c = 1, grid.cols do
            local cell = grid.cells[r][c]
            if not cell.isFault and cell.state == FaultTracerGrid.STATE_HIDDEN then
                table.insert(candidates, { row = r, col = c, number = cell.number })
            end
        end
    end

    table.sort(candidates, function(a, b) return a.number < b.number end)

    local revealed = 0
    for _, candidate in ipairs(candidates) do
        if revealed >= count then break end

        local cell = grid.cells[candidate.row][candidate.col]
        if cell.state == FaultTracerGrid.STATE_HIDDEN then
            if cell.number == 0 then
                -- Cascade reveal
                local cascaded = FaultTracerGrid.cascadeReveal(grid, candidate.row, candidate.col)
                for _, pos in ipairs(cascaded) do
                    table.insert(allRevealed, pos)
                end
            else
                cell.state = FaultTracerGrid.STATE_REVEALED
                table.insert(allRevealed, { row = candidate.row, col = candidate.col })
            end
            revealed = revealed + 1
        end
    end

    return allRevealed
end

--[[
    Probe a cell (player action).
    Returns the result of probing.

    @param grid table
    @param row number
    @param col number
    @return table {success=bool, isFault=bool, cascaded=table|nil, cell=table}
]]
function FaultTracerGrid.probeCell(grid, row, col)
    if row < 1 or row > grid.rows or col < 1 or col > grid.cols then
        return { success = false }
    end

    local cell = grid.cells[row][col]

    if cell.state ~= FaultTracerGrid.STATE_HIDDEN then
        return { success = false }
    end

    grid.probeCount = grid.probeCount + 1

    if cell.isFault then
        -- Hit a fault! Reveal it with penalty
        cell.state = FaultTracerGrid.STATE_REVEALED
        grid.faultHits = grid.faultHits + 1
        grid.faultsFound = grid.faultsFound + 1
        return { success = true, isFault = true, cascaded = nil, cell = cell }
    end

    -- Safe cell
    if cell.number == 0 then
        -- Zero cell - cascade reveal
        local cascaded = FaultTracerGrid.cascadeReveal(grid, row, col)
        return { success = true, isFault = false, cascaded = cascaded, cell = cell }
    end

    -- Number cell - just reveal
    cell.state = FaultTracerGrid.STATE_REVEALED
    return { success = true, isFault = false, cascaded = nil, cell = cell }
end

--[[
    Flag a cell with a fault type guess.

    @param grid table
    @param row number
    @param col number
    @param faultType string "corroded"|"cracked"|"seized"
    @return bool success
]]
function FaultTracerGrid.flagCell(grid, row, col, faultType)
    if row < 1 or row > grid.rows or col < 1 or col > grid.cols then
        return false
    end

    local cell = grid.cells[row][col]

    if cell.state == FaultTracerGrid.STATE_REVEALED then
        -- Can flag revealed faults (from probe hits)
        if cell.isFault then
            cell.previousState = FaultTracerGrid.STATE_REVEALED
            cell.flaggedType = faultType
            cell.state = FaultTracerGrid.STATE_FLAGGED
            return true
        end
        return false
    end

    if cell.state == FaultTracerGrid.STATE_HIDDEN then
        cell.previousState = FaultTracerGrid.STATE_HIDDEN
        cell.flaggedType = faultType
        cell.state = FaultTracerGrid.STATE_FLAGGED
        grid.faultsFound = grid.faultsFound + 1
        return true
    end

    if cell.state == FaultTracerGrid.STATE_FLAGGED then
        -- Update existing flag type
        cell.flaggedType = faultType
        return true
    end

    return false
end

--[[
    Unflag a cell (return to hidden or revealed state).

    @param grid table
    @param row number
    @param col number
    @return bool success
]]
function FaultTracerGrid.unflagCell(grid, row, col)
    if row < 1 or row > grid.rows or col < 1 or col > grid.cols then
        return false
    end

    local cell = grid.cells[row][col]

    if cell.state ~= FaultTracerGrid.STATE_FLAGGED then
        return false
    end

    -- Restore to the state before flagging
    cell.state = cell.previousState or FaultTracerGrid.STATE_HIDDEN
    cell.previousState = nil
    cell.flaggedType = nil

    -- Only decrement faultsFound if returning to hidden (not probe-revealed)
    if cell.state == FaultTracerGrid.STATE_HIDDEN then
        grid.faultsFound = grid.faultsFound - 1
    end

    return true
end

--[[
    Reveal a hint cell (safe cell at 1.5x cost).
    Picks the most useful unrevealed safe cell.

    @param grid table
    @return table|nil {row, col} of revealed cell, or nil if none available
]]
function FaultTracerGrid.revealHint(grid)
    -- Find best hint: prefer cells adjacent to faults (most informative)
    local candidates = {}

    for r = 1, grid.rows do
        for c = 1, grid.cols do
            local cell = grid.cells[r][c]
            if not cell.isFault and cell.state == FaultTracerGrid.STATE_HIDDEN then
                table.insert(candidates, { row = r, col = c, number = cell.number })
            end
        end
    end

    if #candidates == 0 then
        return nil
    end

    -- Sort by number descending (higher numbers = more informative)
    table.sort(candidates, function(a, b) return a.number > b.number end)

    local chosen = candidates[1]
    local cell = grid.cells[chosen.row][chosen.col]

    if cell.number == 0 then
        FaultTracerGrid.cascadeReveal(grid, chosen.row, chosen.col)
    else
        cell.state = FaultTracerGrid.STATE_REVEALED
    end

    grid.hintsUsed = grid.hintsUsed + 1

    return { row = chosen.row, col = chosen.col }
end

--[[
    Quick Scan: auto-probe all cells and auto-identify all faults.
    Caps repair quality at 60%.

    @param grid table
    @return table {probedCount, faultCount}
]]
function FaultTracerGrid.quickScan(grid)
    local probedCount = 0
    local faultCount = 0

    grid.quickScanUsed = true

    for r = 1, grid.rows do
        for c = 1, grid.cols do
            local cell = grid.cells[r][c]
            if cell.state == FaultTracerGrid.STATE_HIDDEN then
                if cell.isFault then
                    cell.previousState = FaultTracerGrid.STATE_HIDDEN
                    cell.state = FaultTracerGrid.STATE_FLAGGED
                    cell.flaggedType = cell.faultType  -- Auto-correct type
                    faultCount = faultCount + 1
                    grid.faultsFound = grid.faultsFound + 1
                else
                    cell.state = FaultTracerGrid.STATE_REVEALED
                end
                probedCount = probedCount + 1
            end
        end
    end

    grid.probeCount = grid.probeCount + probedCount

    return { probedCount = probedCount, faultCount = faultCount }
end

--[[
    Check if all faults have been flagged.

    @param grid table
    @return bool
]]
function FaultTracerGrid.allFaultsFlagged(grid)
    for _, pos in ipairs(grid.faultPositions) do
        local cell = grid.cells[pos.row][pos.col]
        if cell.state ~= FaultTracerGrid.STATE_FLAGGED then
            return false
        end
    end
    return true
end

--[[
    Calculate total oil used from grid state.
    Single source of truth for oil display during gameplay and results.

    @param grid table
    @return number Total oil consumed by probing and hints
]]
function FaultTracerGrid.getOilUsed(grid)
    local safeCells = grid.probeCount - grid.faultHits
    local probeOil = (safeCells * 0.3) + (grid.faultHits * 0.9)
    local hintOil = grid.hintsUsed * 0.45
    local total = probeOil + hintOil

    if grid.quickScanUsed then
        total = total + probeOil  -- Quick scan doubles probe cost
    end

    return total
end

--[[
    Calculate repair results after all faults are flagged.

    @param grid table
    @return table {reliabilityGain, ceilingGain, totalOilUsed, faultResults, diagnosisAccuracy, probeEfficiency}
]]
function FaultTracerGrid.calculateResults(grid)
    local results = {
        faultResults = {},
        correctCount = 0,
        incorrectCount = 0,
        totalOilUsed = 0,
        diagnosisAccuracy = 0,
        probeEfficiency = 0,
        reliabilityGain = 0,
        ceilingGain = 0,
    }

    -- Evaluate each fault
    for _, pos in ipairs(grid.faultPositions) do
        local cell = grid.cells[pos.row][pos.col]
        local isCorrect = (cell.flaggedType == cell.faultType)

        local faultResult = {
            row = pos.row,
            col = pos.col,
            actualType = cell.faultType,
            guessedType = cell.flaggedType,
            isCorrect = isCorrect,
        }

        -- Oil cost per fault type
        local baseCost = 1.0  -- corroded
        if cell.faultType == FaultTracerGrid.FAULT_CRACKED then
            baseCost = 2.0
        elseif cell.faultType == FaultTracerGrid.FAULT_SEIZED then
            baseCost = 4.0
        end

        if isCorrect then
            faultResult.oilCost = baseCost
            results.correctCount = results.correctCount + 1
        else
            faultResult.oilCost = baseCost * 3.0
            results.incorrectCount = results.incorrectCount + 1
        end

        results.totalOilUsed = results.totalOilUsed + faultResult.oilCost
        table.insert(results.faultResults, faultResult)
    end

    -- Add probing/hint oil costs (single source of truth)
    results.totalOilUsed = results.totalOilUsed + FaultTracerGrid.getOilUsed(grid)

    -- Diagnosis accuracy
    local totalFaults = #grid.faultPositions
    if totalFaults > 0 then
        results.diagnosisAccuracy = results.correctCount / totalFaults
    else
        results.diagnosisAccuracy = 1.0
    end

    -- Quick scan caps accuracy effect at 0.6
    if grid.quickScanUsed then
        results.diagnosisAccuracy = math.min(results.diagnosisAccuracy, 0.6)
    end

    -- Probe efficiency (no fault hits = 1.0, 1 hit = 0.9, 2+ = 0.8)
    if grid.faultHits == 0 then
        results.probeEfficiency = 1.0
    elseif grid.faultHits == 1 then
        results.probeEfficiency = 0.9
    else
        results.probeEfficiency = 0.8
    end

    -- Calculate reliability gain
    results.reliabilityGain = grid.params.baseGain * results.diagnosisAccuracy * results.probeEfficiency
    results.ceilingGain = grid.params.ceilingGain * results.diagnosisAccuracy * results.probeEfficiency

    return results
end

--[[
    Get count of remaining hidden cells (not revealed, not flagged).

    @param grid table
    @return number
]]
function FaultTracerGrid.getHiddenCount(grid)
    local count = 0
    for r = 1, grid.rows do
        for c = 1, grid.cols do
            if grid.cells[r][c].state == FaultTracerGrid.STATE_HIDDEN then
                count = count + 1
            end
        end
    end
    return count
end

--[[
    Get count of flagged cells.

    @param grid table
    @return number
]]
function FaultTracerGrid.getFlaggedCount(grid)
    local count = 0
    for r = 1, grid.rows do
        for c = 1, grid.cols do
            if grid.cells[r][c].state == FaultTracerGrid.STATE_FLAGGED then
                count = count + 1
            end
        end
    end
    return count
end

UsedPlus.logInfo("FaultTracerGrid loaded - Minesweeper grid engine ready")
