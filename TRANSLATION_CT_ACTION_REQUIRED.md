# ACTION REQUIRED: Traditional Chinese Translation

**Date:** 2026-02-01
**Priority:** Medium (Blocks Taiwan market)
**Scope:** 1,944 untranslated keys in `translations/translation_ct.xml`

---

## Situation

The Traditional Chinese (CT) translation file is currently a direct copy of the English source with **no actual translation**. All other major languages (German, French, Spanish) have been properly translated, but CT displays English text to Chinese-speaking players.

### Quick Comparison

```
EN: "Finance Vehicle"          ✅ Source
DE: "Finanzvehikel"           ✅ Translated
FR: "Véhicule financier"      ✅ Translated
ES: "Vehículo financiero"     ✅ Translated
CT: "Finance Vehicle"         ❌ NOT TRANSLATED (English text!)
```

---

## Impact

- **User Experience:** Taiwan players see ALL text in English (unusable for non-English speakers)
- **Market Reach:** Cannot effectively serve Traditional Chinese market
- **Mod Rating:** May receive negative reviews from Chinese players expecting localization

---

## Options

### Option 1: Professional Translator (Recommended)

**Best for:** High-quality, natural-sounding translation

- **Requirements:** Native Traditional Chinese (Taiwan) speaker with financial/gaming terminology experience
- **Time:** 20-30 hours of translation work
- **Cost:** Free if you know someone; otherwise ~$1,200-2,500 USD via translation service
- **Deliverables:** Fully translated `translation_ct.xml` file matching quality of DE/FR/ES versions

**Resources Provided:**
- ✅ `translations/CT_TRANSLATION_STATUS.md` - Detailed guide with sample translations and terminology glossary
- ✅ `tools/findUntranslated.js` - Script to find untranslated keys
- ✅ `translations/translation_sync.js check` - Validation tool

### Option 2: Machine Translation + Human Review

**Best for:** Quick draft with lower budget

- **Process:**
  1. Use Google Translate API or DeepL to bulk translate
  2. Hire editor to review and fix financial terminology
  3. Native speaker QA pass
- **Time:** 5-10 hours review + QA
- **Cost:** ~$300-600 USD
- **Quality:** Functional but may have awkward phrasing

### Option 3: Phased Approach

**Best for:** Limited budget, prioritize critical strings

- **Phase 1:** Translate critical user-facing strings (~500 keys: dialogs, errors, buttons)
- **Phase 2:** Feature content (~800 keys: finance/marketplace descriptions)
- **Phase 3:** Supplementary (~644 keys: advanced help text, edge cases)

Each phase is independently useful and can be done by different translators.

### Option 4: Community Translation

**Best for:** Open-source / community-driven mods

- Create translation template/spreadsheet
- Post on Taiwan farming sim forums/Discord requesting volunteer translators
- Review and merge community contributions

---

## Critical Requirements (For ANY Translator)

### ⚠️ FORMAT SPECIFIERS MUST BE PRESERVED EXACTLY

**CRITICAL:** Many strings contain format codes that MUST NOT be changed or game will crash:

```xml
<!-- CORRECT ✅ -->
<e k="example" v="價格：$%.2f（%d%%）" />  <!-- Preserves %.2f and %d -->

<!-- WRONG ❌ - WILL CRASH GAME -->
<e k="example" v="價格：美元（百分比）" />  <!-- Missing format codes! -->
```

**Format codes to preserve:**
- `%s` - String placeholder
- `%d` - Integer
- `%.1f` - Decimal (1 digit)
- `%.2f` - Decimal (2 digits)
- `{0}`, `{1}` - Numbered placeholders

### Validation Checklist

After translation, translator MUST verify:

- [ ] All format specifiers preserved exactly (`%s`, `%d`, `%.1f`, `{0}`, etc.)
- [ ] No `[EN]` prefixes remaining
- [ ] Consistent terminology throughout (e.g., always use same word for "finance", "lease", etc.)
- [ ] Run `cd translations && node translation_sync.js check` - must pass
- [ ] Test in-game: Open dialogs, trigger errors, verify text displays correctly

---

## Immediate Action

**Decision needed:** Which option above will you pursue?

1. If **Option 1** → Contact translator/service, provide `CT_TRANSLATION_STATUS.md` as briefing
2. If **Option 2** → Set up machine translation pipeline, hire editor
3. If **Option 3** → Decide which phase to start with, assign translator
4. If **Option 4** → Create community translation project

**Alternatively:** If Traditional Chinese market is not a priority, consider removing `translation_ct.xml` entirely so game falls back to English (cleaner than shipping non-translated file).

---

## Files Reference

| File | Purpose |
|------|---------|
| `translations/translation_en.xml` | Source English text (DO NOT MODIFY) |
| `translations/translation_ct.xml` | Target file needing translation |
| `translations/CT_TRANSLATION_STATUS.md` | Full translation guide with samples |
| `tools/findUntranslated.js` | Find untranslated keys |
| `translations/translation_sync.js` | Validate format after translation |

---

## Contact

If you have questions or need clarification on translation requirements, please review `CT_TRANSLATION_STATUS.md` first - it contains detailed examples, terminology glossary, and sample translations.

**This file created by:** Claude Code AI Assistant
**Date:** 2026-02-01
