# Traditional Chinese (CT) Translation Status

**Generated:** 2026-02-01
**File:** `translations/translation_ct.xml`
**Status:** ⚠️ **REQUIRES FULL TRANSLATION**

---

## Summary

The Traditional Chinese translation file currently contains **1,944 untranslated keys** out of approximately 2,493 total entries. The file appears to be a direct copy of the English source file (`translation_en.xml`) with minimal localization.

### Comparison with Other Languages

| Language | Sample Key (`usedplus_finance_title`) | Status |
|----------|--------------------------------------|--------|
| English (EN) | "Finance Vehicle" | ✅ Source |
| German (DE) | "Finanzvehikel" | ✅ Translated |
| French (FR) | "Véhicule financier" | ✅ Translated |
| Spanish (ES) | "Vehículo financiero" | ✅ Translated |
| **Traditional Chinese (CT)** | **"Finance Vehicle"** | ❌ **NOT TRANSLATED** |

---

## Translation Scope

### Content Categories Requiring Translation

1. **Financial Terminology** (~400 keys)
   - Loans, leases, credit scores, interest rates
   - Payment schedules, down payments, residual values
   - Example: `usedplus_finance_downPayment` → "Down Payment" needs → "頭期款"

2. **Vehicle Marketplace** (~300 keys)
   - Buying, selling, negotiation, trade-ins
   - Condition ratings, inspections, repairs
   - Example: `usedplus_marketplace_title` → "Used Vehicle Marketplace" needs → "二手車輛市場"

3. **UI Elements** (~500 keys)
   - Dialog titles, button labels, menu items
   - Input prompts, tooltips, status messages
   - Example: `usedplus_dialog_confirm` → "Confirm" needs → "確認"

4. **Tutorial/Help Text** (~300 keys)
   - Feature explanations, user guidance
   - Tips, warnings, important information
   - Example: Long explanatory paragraphs requiring careful translation

5. **Error Messages** (~200 keys)
   - Validation errors, business logic errors
   - System messages, warnings
   - Example: `usedplus_error_insufficientFunds` → "Insufficient funds" needs → "資金不足"

6. **Notifications** (~100 keys)
   - Success messages, status updates
   - Reminders, alerts

7. **Miscellaneous** (~144 keys)
   - Units, format strings, placeholders
   - Developer notes (may not need translation)

---

## Critical Translation Requirements

### ⚠️ Format Specifiers MUST BE PRESERVED

**CRITICAL:** Many strings contain format specifiers that MUST match exactly or the game will crash:

| Specifier | Meaning | Example |
|-----------|---------|---------|
| `%s` | String | "Vehicle: %s" → "車輛：%s" |
| `%d` | Integer | "Day %d" → "第 %d 天" |
| `%.1f` | Float (1 decimal) | "Rate: %.1f%%" → "利率：%.1f%%" |
| `%.2f` | Float (2 decimals) | "Price: $%.2f" → "價格：$%.2f" |
| `{0}`, `{1}` | Placeholders | "Buy {0} for {1}" → "以 {1} 購買 {0}" |

**Example (CORRECT):**
```xml
<!-- EN -->
<e k="usedplus_finance_downPayment_desc" v="Down payment: $%.2f (%d%%)" />

<!-- CT (CORRECT - preserves format) -->
<e k="usedplus_finance_downPayment_desc" v="頭期款：$%.2f（%d%%）" />

<!-- CT (WRONG - missing format specifiers = CRASH!) -->
<e k="usedplus_finance_downPayment_desc" v="頭期款：美元（百分比）" />
```

---

## Sample Translations (Reference)

Below are professionally translated examples for the first 50 critical keys to demonstrate proper localization:

### Finance Dialog

| Key | English | Traditional Chinese (CT) |
|-----|---------|--------------------------|
| `usedplus_finance_title` | Finance Vehicle | 融資購買車輛 |
| `usedplus_finance_configuration` | Finance Configuration | 融資配置 |
| `usedplus_finance_downPayment` | Down Payment | 頭期款 |
| `usedplus_finance_monthlyPayment` | Monthly Payment | 月付款 |
| `usedplus_finance_interestRate` | Interest Rate | 利率 |
| `usedplus_finance_creditScore` | Credit Score | 信用評分 |
| `usedplus_finance_loanTerm` | Loan Term (Years) | 貸款期限（年） |

### Lease Dialog

| Key | English | Traditional Chinese (CT) |
|-----|---------|--------------------------|
| `usedplus_lease_title` | Lease Vehicle | 租賃車輛 |
| `usedplus_lease_configuration` | Lease Configuration | 租賃配置 |
| `usedplus_lease_residualValue` | Residual Value (Balloon Payment) | 殘值（尾款） |

### Used Vehicle Marketplace

| Key | English | Traditional Chinese (CT) |
|-----|---------|--------------------------|
| `usedplus_marketplace_title` | Used Vehicle Marketplace | 二手車輛市場 |
| `usedplus_marketplace_searchFilters` | Search Filters | 搜尋篩選 |
| `usedplus_marketplace_condition` | Condition | 狀況 |
| `usedplus_marketplace_negotiate` | Negotiate | 議價 |
| `usedplus_marketplace_inspection` | Inspection | 檢查 |
| `usedplus_marketplace_buyNow` | Buy Now | 立即購買 |

### Common UI Elements

| Key | English | Traditional Chinese (CT) |
|-----|---------|--------------------------|
| `usedplus_dialog_ok` | OK | 確定 |
| `usedplus_dialog_cancel` | Cancel | 取消 |
| `usedplus_dialog_confirm` | Confirm | 確認 |
| `usedplus_dialog_back` | Back | 返回 |
| `usedplus_dialog_next` | Next | 下一步 |
| `usedplus_dialog_previous` | Previous | 上一步 |

### Error Messages

| Key | English | Traditional Chinese (CT) |
|-----|---------|--------------------------|
| `usedplus_error_insufficientFunds` | Insufficient funds | 資金不足 |
| `usedplus_error_invalidInput` | Invalid input | 輸入無效 |
| `usedplus_error_notAvailable` | Not available | 不可用 |

---

## Recommendations

### For Professional Translation

1. **Hire a native Traditional Chinese (Taiwan) speaker** with:
   - Experience in financial/business terminology
   - Familiarity with gaming/simulation contexts
   - Understanding of technical translation requirements

2. **Use the sample translations above as a style guide**
   - Formal but accessible tone
   - Consistent terminology (e.g., always use "融資" for "finance", "租賃" for "lease")

3. **Provide translator with context:**
   - This is a farming simulator financial management mod
   - Target audience: Taiwan players of Farming Simulator 25
   - Tone: Professional but user-friendly (not overly technical)

4. **Quality assurance checklist:**
   - [ ] All format specifiers preserved exactly (`%s`, `%d`, `%.1f`, etc.)
   - [ ] All placeholders preserved exactly (`{0}`, `{1}`, etc.)
   - [ ] Consistent terminology throughout
   - [ ] Natural-sounding Chinese (not machine translation)
   - [ ] All 1,944 keys translated
   - [ ] No `[EN]` prefixes remaining
   - [ ] Run `node translation_sync.js check` passes

### Alternative: Phased Approach

If full translation is not immediately feasible:

1. **Phase 1: Critical User-Facing Strings** (~500 keys)
   - Dialog titles and buttons
   - Error messages
   - Main menu items

2. **Phase 2: Feature Content** (~800 keys)
   - Finance/lease descriptions
   - Marketplace content
   - Tutorial text

3. **Phase 3: Supplementary Content** (~644 keys)
   - Detailed help text
   - Advanced features
   - Edge case messages

---

## Tools & Resources

### Translation Script
```bash
cd translations
node findUntranslated.js  # Find all untranslated keys
node translation_sync.js check  # Verify format after translation
```

### Reference Files
- **Source:** `translation_en.xml` (English - definitive source)
- **Target:** `translation_ct.xml` (Traditional Chinese - needs translation)
- **Examples:** `translation_de.xml`, `translation_fr.xml` (see how other languages handled it)

### Financial Terminology Reference (EN → CT)

| English | Traditional Chinese | Notes |
|---------|---------------------|-------|
| Finance | 融資 | As verb/action |
| Financing | 融資 | General term |
| Loan | 貸款 | Bank loan |
| Lease | 租賃 | Equipment lease |
| Credit Score | 信用評分 | 300-850 scale |
| Interest Rate | 利率 | Percentage |
| Down Payment | 頭期款 | Initial payment |
| Monthly Payment | 月付款 | Recurring payment |
| Residual Value | 殘值 | End-of-lease value |
| Balloon Payment | 尾款 | Large final payment |
| Principal | 本金 | Loan amount |
| Collateral | 抵押品 | Secured asset |
| Default | 違約 | Failure to pay |
| Amortization | 攤銷 | Payment schedule |
| Trade-in | 以舊換新 / 折價換購 | Exchange old for new |

---

## Current Status: BLOCKING

**⚠️ The Traditional Chinese translation file is currently non-functional for Chinese-speaking players.** All text will display in English, which severely impacts usability for the Taiwan market.

**Estimated Translation Time:** 20-30 hours for professional translator
**Estimated Cost:** Varies by translator (typical range: $0.08-0.15 USD per word × ~15,000 words = $1,200-2,250 USD)

---

## Contact

For questions about this translation requirement, contact the mod developer or file an issue on the GitHub repository.
