-- Anchor-unit candidate measurement for Tanda 6 F-4 (dev/code-review-
-- tanda6-response.md Phase 3, SSB.5).
--
-- The three candidates:
--   A: anchor by CHARACTER COUNT against the already-measured widest sample
--      (no per-frame measurement; assumes fixed-width digits)
--   B: a separate, UNMEMOISED measuring function (exact; one lcd.sizeText
--      per text change)
--   C: drop anchorUnit; put value+unit in one LVGL container and let it
--      align (the firmware idiom, value.cpp)
--
-- C is structurally INFEASIBLE in the Lua binding: every Lua object is
-- created flat under lvglManager->getCurrentParent() (lua_lvgl_widget.cpp
-- LvglWidgetBox::build), so a Lua `box` can never have children - its flex
-- layout lays out zero objects. `children` is a tolerated-but-ignored key
-- (lua_lvgl_widget.cpp:659). There is no object parenting in the Lua API.
--
-- A and B cannot be told apart under the headless mock, whose sizeText is
-- LINEAR (#chars * k): there A == B == exact by construction. Real EdgeTX
-- fonts are PROPORTIONAL (a "1" is narrower than a "0"), so this probe
-- swaps a proportional metric into the mock and measures the unit x
-- displacement A would introduce vs the exact B across a value matrix.
--
-- Usage: lua5.3 dev/measure_anchor.lua

-- Proportional digit widths, roughly DejaVu-Sans-like (fraction of the
-- widest digit). Only the RELATIVE numbers matter for the comparison.
local CHAR_W = {
  ["1"] = 0.55, ["2"] = 0.90, ["3"] = 0.90, ["4"] = 0.90, ["5"] = 0.90,
  ["6"] = 0.90, ["7"] = 0.80,  ["8"] = 0.95, ["9"] = 0.90, ["0"] = 0.95,
  ["-"] = 0.60, ["."] = 0.50,  [","] = 0.50, ["%"] = 1.00, [" "] = 0.35,
  [":"] = 0.40,
}

local function width(text, unit)
  local w = 0
  for i = 1, #text do
    w = w + (CHAR_W[string.sub(text, i, i)] or 0.9) * unit
  end
  return w
end

local function sampleChars(widestSample)
  return #widestSample
end

local samples = { "-100.0", "-100.00", "-10000.00", "-00:00:00", "16.80" }
local values = {
  "7", "8", "78", "22", "45", "55", "100", "1500", "0", "3.85", "55.0",
  "-12", "92", "3.1", "100.00", "16.80",
}

print("Candidate comparison for F-4 (proportional font model, u = digit unit)")
print("unit x displacement = (estW - exactW) / 2  vs the exact anchor")
print("")
print(string.format("%-12s %-10s %8s %8s %9s",
  "sample", "value", "exactW", "estW(A)", "disp px/u"))
local worst = { d = 0 }
for _, sample in ipairs(samples) do
  local vw = width(sample, 1)          -- widest sample, in unit digits
  local nChars = sampleChars(sample)
  for _, v in ipairs(values) do
    local exact = width(v, 1)
    local est = vw * #v / nChars      -- candidate A
    local disp = math.abs(est - exact) / 2
    if disp > worst.d then worst = { d = disp, sample = sample, v = v,
      exact = exact, est = est } end
    print(string.format("%-12s %-10s %8.2f %8.2f %9.2f",
      sample, v, exact, est, disp))
  end
end
print("")
print(string.format("worst displacement: %.2f digit units (%s, sample %s,"
  .. " exact %.2f / est %.2f)", worst.d, worst.v, worst.sample,
  worst.exact, worst.est))
print("at a 24 px digit (0.55x font cell) that is roughly "
  .. string.format("%.1f px of unit x drift per frame-class value", worst.d * 24))
print("")
print("verdict: B keeps the unit EXACT on proportional fonts for one")
print("lcd.sizeText call per value change; A trades exactness for zero")
print("measurement. B is pixel-identical to the frozen baseline by")
print("construction (same sizeText source, just unmemoized).")
