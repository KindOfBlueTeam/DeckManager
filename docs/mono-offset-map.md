# Hearthstone Mono Offset Map

**Last validated:** April 10, 2026  
**Hearthstone version:** Current live (macOS)  
**Unity/Mono variant:** Mono embedded in Unity (runtime v4.0.30319)

---

## How to Read This Document

All offsets are in hexadecimal. `struct+0x28` means "read 8 bytes at address `struct_base + 0x28`". All pointers are 64-bit (8 bytes). Integer sizes are noted where relevant.

This document is the source of truth for DeckRipperHS's memory reading. If Hearthstone updates break extraction, re-run diagnostics and update the offsets here first, then update the code.

---

## 1. Mono Runtime Navigation

### Finding the Root Domain

The root domain is found by scanning readable memory regions for a structure whose `domain_assemblies` pointer (+0xC8) leads to a GSList of MonoAssembly pointers with recognizable names (`"mscorlib"`, `"Assembly-CSharp"`, etc.).

| Structure | Offset | Type | Description |
|-----------|--------|------|-------------|
| MonoDomain | +0xC8 | `GSList*` | Linked list of loaded assemblies |

### GSList (GLib Singly-Linked List)

| Offset | Type | Description |
|--------|------|-------------|
| +0x00 | `void*` | `data` — pointer to MonoAssembly |
| +0x08 | `GSList*` | `next` — next node in list |

### MonoAssembly

| Offset | Type | Description |
|--------|------|-------------|
| +0x10 | `char*` | Assembly name string (e.g., `"Assembly-CSharp"`) |
| +0x60 | `MonoImage*` | Pointer to the loaded image metadata |

---

## 2. MonoImage (Assembly-CSharp)

Found via `MonoAssembly+0x60`.

| Offset | Type | Value/Description |
|--------|------|-------------------|
| +0x00 | int | `ref_count` (typically 2) |
| +0x20 | `char*` | Full DLL path |
| +0x28 | `char*` | Full DLL path (duplicate) |
| +0x30 | `char*` | Assembly name: `"Assembly-CSharp"` |
| +0x38 | `char*` | Filename: `"Assembly-CSharp.dll"` |
| +0x48 | `char*` | Runtime version: `"v4.0.30319"` |
| +0x70 | `char*` | PE metadata signature: `"BSJB"` |

**Note:** The class cache is NOT at the standard Mono offset (+0x170). This Unity variant uses a modified layout. We bypass the class cache entirely using direct string scanning.

---

## 3. MonoClass Layout

Found by scanning memory for class name strings, then finding pointers to those strings and validating the image pointer.

### Standard Classes (e.g., NetCacheCollection)

| Offset | Type | Description |
|--------|------|-------------|
| +0x00 | flags | Internal flags (e.g., `0x0000002801000002`) |
| +0x08 | flags | More internal flags |
| +0x10 | `void*` | Type-related pointer |
| +0x18 | `MonoClass*` | **Parent class pointer** (see note below) |
| +0x20 | `MonoImage*` | **Image pointer** — used to validate class belongs to Assembly-CSharp |
| +0x28 | `char*` | **Class name** (e.g., `"NetCacheCollection"`) |
| +0x30 | `char*` | **Namespace** (e.g., `""` for Hearthstone classes) |
| +0x38 | uint64 | Type token + flags |
| +0xB8 | `void*` | Runtime info / method table area |
| +0xE0 | int | Field count (approximate area) |
| +0xF0+ | inline | **Field descriptors** (see below) |

### Parent Class Variant (e.g., NetCache)

The parent class at +0x18 has a **shifted layout** due to self-referential `element_class` and `cast_class` pointers:

| Offset | Type | Description |
|--------|------|-------------|
| +0x00 | `MonoClass*` | `element_class` (points to self) |
| +0x08 | `MonoClass*` | `cast_class` (points to self) |
| +0x10 | `void*` | `supertypes` pointer |
| +0x18 | flags | (same as standard +0x00) |
| +0x38 | `MonoImage*` | **Image pointer** (shifted from standard +0x20) |
| +0x40 | `char*` | **Class name** (shifted from standard +0x28) |

**Important:** When resolving class names through vtables, try BOTH name offsets (+0x28 and +0x40) to handle both layouts.

---

## 4. Field Descriptors

Field descriptors appear inline in the MonoClass structure starting around +0xF0. Each descriptor is **0x20 bytes** (32 bytes):

| Field Descriptor Offset | Type | Description |
|------------------------|------|-------------|
| +0x00 | `MonoType*` | Field type pointer |
| +0x08 | `char*` | **Field name** (e.g., `"<Stacks>k__BackingField"`) |
| +0x10 | `MonoClass*` | Parent class pointer |
| +0x18 | `uint32` | **Instance field offset** — byte position within a live object |

To find fields: scan class structure from +0xE0 to +0x300 looking for valid string pointers that resolve to field-name-like strings, then read the uint32 at `stringPointerAddr + 0x10` for the instance offset.

---

## 5. NetCacheCollection

### Class Info

| Property | Value |
|----------|-------|
| Class name | `NetCacheCollection` |
| Namespace | `""` (empty) |
| Parent | `NetCache` (name at parent+0x40) |
| Assembly | Assembly-CSharp |

### Instance Field Offsets

| Field | Instance Offset | Type | Description |
|-------|----------------|------|-------------|
| `<Stacks>k__BackingField` | **+0x10** | `List<CardStack>` | The card collection |
| `CoreCardsUnlockedPerClass` | **+0x18** | `Map<K,V>` | Per-class unlock data |
| `TotalCardsOwned` | **+0x20** | `int32` | Total copies owned |

### Finding Live Instances (Quick Scan Fingerprint)

Pattern-match on heap (read-write memory regions) for:

```
+0x00: valid pointer (vtable)
+0x10: valid pointer → class name contains "List"
+0x18: valid pointer (not packed int32 pair)
+0x20: int32 in [200, 20000], upper 32 bits = 0
+0x24: pre-filter — bytes must be 0x00000000 (upper half of TotalCardsOwned)
```

Then verify first card in the list has a valid card ID string (regex: `^[A-Z][A-Z0-9_]`).

---

## 6. Mono Collection Objects

### List\`1 (System.Collections.Generic.List)

| Offset | Type | Description |
|--------|------|-------------|
| +0x10 | `T[]` | `_items` — backing array pointer |
| +0x18 | `int32` | `_size` — number of valid entries |

### Mono Array (T[])

| Offset | Type | Description |
|--------|------|-------------|
| +0x10 | `uint32` | Array length (capacity) |
| +0x20 | `T` | First element (8 bytes per reference type element) |

Elements at: `array_base + 0x20 + (index * 8)`

### Mono String (System.String)

| Offset | Type | Description |
|--------|------|-------------|
| +0x10 | `int32` | String length (character count) |
| +0x14 | `char[]` | UTF-16LE encoded characters |

---

## 7. CardStack

Each entry in the Stacks list. **Fully mapped as of Phase 12 (April 10, 2026).**

| Offset | Size | Type | Description |
|--------|------|------|-------------|
| +0x00 | 8 | `void*` | vtable → CardStack class |
| +0x08 | 8 | — | null (padding/sync block) |
| +0x10 | 8 | `CardDefinition*` | **Pointer to card definition** |
| +0x18 | 8 | `int64` | **Acquisition timestamp** (Windows FILETIME — see Section 11) |
| +0x20 | 4 | `int32` | **Count** — number of copies |
| +0x24 | 4 | `int32` | **NumSeen** — usually equals Count |
| +0x28 | 4 | `int32` | Always 0 |
| +0x2C | 4 | `int32` | Always 0 |
| +0x30 | 8 | `void*` | Pointer to related object (varies per card — 125 distinct values across 3570 cards) |
| +0x34 | 4 | `int32` | Low-cardinality field: 3 values observed (32758: 3372x, 32757: 152x, 0: 46x). Purpose unknown. Possibly encodes high bits of the +0x30 pointer. |
| +0x38 | 8 | — | Always 0 |

### Byte at +0x14

Always `0x01`. This is the low byte of the CardDefinition pointer's high word — not a separate field.

---

## 8. CardDefinition

Referenced by CardStack+0x10.

| Offset | Type | Description |
|--------|------|-------------|
| +0x00 | `void*` | vtable → CardDefinition class |
| +0x08 | — | null |
| +0x10 | `MonoString*` | **Card ID string** (e.g., `"EX1_055"`, `"RLK_511"`) |
| +0x18 | `int32` | **Premium flag** (0=normal, 1=golden) |
| +0x20–0x28 | — | null fields |
| +0x30 | `CardStack*` | Back-pointer to parent CardStack |

---

## 9. VTable / Class Name Resolution

To identify an object's class name from its address:

1. Read vtable pointer at `object+0x00`
2. Try class pointer at vtable offsets: `+0x00, +0x08, +0x10, +0x18, +0x20, +0x28, +0x30`
3. For each candidate class pointer, try name at: `+0x28` (standard) and `+0x40` (parent-style)
4. Validate: name should be ASCII, start with a letter, length 2-100

```
object → vtable → klass → name
```

The klass offset within the vtable is **not fixed** in this Mono version. The brute-force check across common offsets is required.

---

## 10. Deck-Related Classes (Discovered)

From Phase 9 diagnostics. These classes exist in Assembly-CSharp but have not yet been fully mapped.

### Key Classes to Investigate

| Class | Notes |
|-------|-------|
| `CollectionDeck` | Likely the deck data object (array type `CollectionDeck[]` found) |
| `CollectionDeckInfo` | UI wrapper — has fields for hero power, mana bars, etc. |
| `DeckMaker` | Likely manages deck creation |
| `DeckDetailsDataModel` | Data model for deck details |
| `FreeDeckMgr` | Free deck manager — may also handle trial card grants |
| `DeckRule_DeckSize` | Validates deck size |
| `DeckRule_CountCopiesOfEachCard` | Validates copy limits |
| `PendingDeckCreateData` | Deck creation operation |
| `PendingDeckEditData` | Deck edit operation |
| `DeckFill` | Deck auto-fill logic |

### CollectionDeckInfo Fields (Mapped — UI display wrapper)

| Field | Instance Offset | Type |
|-------|----------------|------|
| `m_root` | +0x20 | pointer |
| `m_visualRoot` | +0x28 | pointer |
| `m_heroPowerParent` | +0x30 | pointer |
| `m_heroPowerName` | +0x38 | pointer |
| `m_heroPowerDescription` | +0x40 | pointer |
| `m_manaCurveTooltipText` | +0x48 | pointer |
| `m_offClicker` | +0x50 | pointer |
| `m_manaBars` | +0x58 | pointer |
| `m_heroCardDef` | +0x60 | pointer |
| `m_activeHeroPowerActor` | +0x68 | pointer |
| `m_defaultHeroPowerActor` | +0x70 | pointer |
| `m_defaultGoldenHeroPowerActor` | +0x78 | pointer |
| `m_heroPowerActors` | +0x80 | pointer |
| `MANA_COST_TEXT_MIN_LOCAL_Z` | +0xA8 | float |
| `MANA_COST_TEXT_MAX_LOCAL_Z` | +0xAC | float |
| `m_wasTouchModeEnabled` | +0xB0 | bool |
| `m_shown` | +0xB1 | bool |

### DeckRule Fields (Mapped — deck validation rules)

| Field | Instance Offset | Type |
|-------|----------------|------|
| `m_id` | +0x30 | int32 |
| `m_deckRulesetId` | +0x34 | int32 |
| `m_appliesToSubsetId` | +0x38 | int32 |
| `m_appliesToSubset` | +0x10 | pointer |
| `m_appliesToIsNot` | +0x3C | int32/bool |
| `m_ruleType` | +0x40 | int32 |
| `m_ruleIsNot` | +0x44 | int32/bool |
| `m_minValue` | +0x48 | int32 |
| `m_maxValue` | +0x4C | int32 |
| `m_tag` | +0x50 | int32 |
| `m_tagMinValue` | +0x54 | int32 |
| `m_tagMaxValue` | +0x58 | int32 |
| `m_stringValue` | +0x18 | pointer (string) |
| `m_errorString` | +0x20 | pointer (string) |
| `m_showInvalidCards` | +0x5C | int32/bool |
| `m_subsets` | +0x28 | pointer (collection) |

### TwistHeroicDeckDataModel Fields (Mapped)

| Field | Instance Offset | Type |
|-------|----------------|------|
| `m_Name` | +0x28 | pointer (string) |
| `m_HeroCard` | +0x30 | pointer |
| `m_RequiredDescription` | +0x38 | pointer (string) |
| `m_RequiredCard` | +0x40 | pointer |
| `m_PassiveCard` | +0x48 | pointer |
| `m_properties` | +0x50 | pointer |
| `m_IsDeckLocked` | +0x58 | bool |
| `m_CardCount` | +0x5C | int32 |

### DeckDetailsDataModel Fields (Mapped)

| Field | Instance Offset | Type |
|-------|----------------|------|
| `m_Product` | +0x28 | pointer |
| `m_MiniSetDetails` | +0x30 | pointer |
| `m_AltDescription` | +0x38 | pointer (string) |
| `m_properties` | +0x40 | pointer |

### DeckPouchDataModel Fields (Mapped)

| Field | Instance Offset | Type |
|-------|----------------|------|
| `m_Pouch` | +0x28 | pointer |
| `m_Details` | +0x30 | pointer |
| `m_properties` | +0x38 | pointer |
| `m_RemainingDust` | +0x40 | int32 |
| `m_TotalDust` | +0x44 | int32 |
| `m_Class` | +0x48 | int32 |
| `m_DeckTemplateId` | +0x4C | int32 |

### CollectionDeck — NOT YET PROBED

`CollectionDeck` is the primary class holding player deck data. The array type
`CollectionDeck[]` was found at `0x7fa844a9c7bd0` (live) / `0x7f844a9c7bd0` (snapshot),
confirming the class exists. **This is a future priority for field offset discovery.**

---

## 11. Card Acquisition Timestamps & Trial Card Detection

**Discovered:** Phase 12-13 (April 10, 2026)

### The Timestamp Field

`CardStack+0x18` contains an 8-byte **Windows FILETIME** — the timestamp when the card entry was added to the collection. A Windows FILETIME is the number of 100-nanosecond intervals since January 1, 1601 UTC.

**Conversion to Unix time:**
```
unixTimestamp = (filetime - 116444736000000000) / 10000000
```

### How Hearthstone Uses Timestamps

Each card acquisition event writes the current server time into +0x18. Key observations from a real collection (3570 CardStack entries, April 10, 2026):

| Timestamp Group | Card Count | Date | What It Is |
|----------------|------------|------|------------|
| Largest group | **1421 cards** (844 unique) | Apr 10, 2026 1:39 PM | **Core/free card grants** — refreshed each session |
| Other groups | 2-91 cards each | Various dates (2016-2026) | **Genuine acquisitions** — pack openings, adventures, rewards |

The largest single-timestamp group contains cards from sets **CORE**, **VANILLA**, **LEGACY**, **EXPERT1**, and **HERO_SKINS** — the free rotating Core Set that Blizzard grants to all players. This group refreshes each time the player logs in (timestamp = session start).

### Trial Cards

As of the Cataclysm expansion (Patch 35.0, March 2026), Blizzard grants **trial access** to two full expansions: **Into the Emerald Dream** (`EMERALD_DREAM`, card ID prefix `EDR`) and **The Lost City of Un'Goro** (`THE_LOST_CITY`, card ID prefix `DINO`).

Trial cards are mixed into `NetCacheCollection.Stacks` alongside owned cards. They include both normal and golden copies. Players can use them freely in deckbuilding. When the trial period ends (next expansion launch), the entries are removed.

### Detection Strategy

Trial and Core-grant cards share the **largest single-timestamp group** (all granted at session start by the server). To classify cards:

1. Read `CardStack+0x18` (8-byte FILETIME) for every card
2. Find the timestamp that appears most frequently → this is the **grant timestamp**
3. For each card in that group, look up its set in HearthstoneJSON:
   - **CORE, VANILLA, LEGACY, EXPERT1, HERO_SKINS** → Core Set grant (free permanent rotation)
   - **EMERALD_DREAM, THE_LOST_CITY** (or whatever the current trial sets are) → **Trial card**
   - Any other set in the grant group → investigate (new trial set or changed Core rotation)
4. All cards NOT in the largest timestamp group → **Owned** (genuinely acquired)

### HearthstoneJSON Set Names Reference

| Set Name | Card ID Prefix | Notes |
|----------|---------------|-------|
| `CORE` | `CORE_` | Current Core Set cards |
| `VANILLA` | `VAN_` | Classic vanilla reprints |
| `LEGACY` | `CS1_`, `CS2_`, `EX1_`, `NEW1_`, `DS1_`, etc. | Legacy Basic/Classic |
| `EXPERT1` | `EX1_`, `CS2_`, etc. | Original Expert (Classic) set |
| `EMERALD_DREAM` | `EDR_` | Trial set (as of Cataclysm) |
| `THE_LOST_CITY` | `DINO_` | Trial set (as of Cataclysm) |
| `CATACLYSM` | `CATA_` | Current expansion |
| `TIME_TRAVEL` | `TIME_`, `END_` | Current expansion companion set |
| `THE_SUNKEN_CITY` | `TSC_`, `TID_` | Older expansion |
| `REVENDRETH` | `REV_`, `MAW_` | Castle Nathria |
| `ISLAND_VACATION` | `VAC_` | Perils in Paradise |
| `WHIZBANGS_WORKSHOP` | `TOY_`, `WORK_` | Whizbang's Workshop |
| `TROLL` | `TRL_` | Rastakhan's Rumble |
| `UNGORO` | `UNG_` | Journey to Un'Goro (original) |
| `LOE` | `LOE_`, `LOEA10_` | League of Explorers adventure |
| `BRM` | `BRM_` | Blackrock Mountain adventure |
| `SPACE` | `GDB_`, `SC_`, `FIR_`, `MIS_` | Space set |
| `TGT` | `AT_` | The Grand Tournament |
| `OG` | `OG_` | Whispers of the Old Gods |
| `GVG` | `GVG_` | Goblins vs Gnomes |

### Maintenance Notes

- **After each Hearthstone patch/DLC:** Re-run `--trial-timestamp` diagnostic to check if trial sets have changed
- **After Core Set rotation (yearly):** The Core grant group will contain different sets; update the Core set list
- Trial card detection is **timestamp-based** (not hardcoded set lists) so the detection itself is resilient — only the UI labeling needs updating when trial sets change
- HSReplay/HSTracker do NOT expose trial card status to users — this is a competitive advantage for DeckRipperHS

---

## 12. Hero Card DbfIds

The deck string format uses `dbfId` to identify heroes. Hearthstone allows multiple hero portraits per class, so the dbfId varies by equipped skin.

### Default Heroes (Hardcoded)

| Class | Hero Name | dbfId |
|-------|-----------|-------|
| Death Knight | The Lich King | 78065 |
| Demon Hunter | Illidan Stormrage | 56550 |
| Druid | Malfurion Stormrage | 274 |
| Hunter | Rexxar | 31 |
| Mage | Jaina Proudmoore | 637 |
| Paladin | Uther Lightbringer | 671 |
| Priest | Anduin Wrynn | 813 |
| Rogue | Valeera Sanguinar | 930 |
| Shaman | Thrall | 1066 |
| Warlock | Gul'dan | 893 |
| Warrior | Garrosh Hellscream | 7 |

### Alternate Hero Resolution

When importing a deck code, the hero dbfId may not match the defaults above (e.g., dbfId `105226` for a Mage deck with an alternate portrait). Resolution order:

1. Check hardcoded hero map
2. Look up dbfId in HearthstoneJSON card database → read `cardClass` field
3. Parse `# Class: Mage` comment line from the Hearthstone clipboard format

---

## Appendix A: Hearthstone Deck String Format

Base64-encoded binary using unsigned LEB128 (varint) encoding:

```
[0 = reserved]
[1 = version]
[format: 1=Wild, 2=Standard]
[hero count (always 1)]
[hero dbfId]
[single-copy count] [dbfIds sorted ascending...]
[double-copy count] [dbfIds sorted ascending...]
[n-copy count] [(dbfId, count) pairs...]
```

### Clipboard Format

When a player copies a deck in Hearthstone, the clipboard contains:

```
### Deck Name
# Class: Mage
# Format: Wild
#
# 1x (1) Card Name
# 2x (2) Another Card
...
#
AAEBAYq2Bgi...==
#
# To use this deck, copy it to your clipboard and create a new deck in Hearthstone
```

To parse: strip all lines starting with `#`, join remaining lines → Base64 deck code. Extract deck name from `### ` prefix line. Extract class from `# Class: ` line as fallback for hero resolution.

---

## Appendix B: Diagnostic Phases

| Phase | Purpose | Key Discovery |
|-------|---------|---------------|
| 1 | MonoImage structure dump | Image layout, name at +0x30, class cache missing at +0x170 |
| 2 | Targeted class search | NetCacheCollection class found but not NetCache |
| 3 | Direct string scanning | NetCacheCollection MonoClass confirmed, name at +0x28 |
| 4 | Parent class exploration | Parent read failed at +0x18 (different layout) |
| 5 | Field descriptor extraction | Stacks at +0x10, TotalCardsOwned at +0x20, parent is "NetCache" at +0x40 |
| 6 | Loose pattern heap scan | 10 false positives — pattern too loose |
| 7 | Strict validated heap scan | **NetCacheCollection instance found!** 3,564 cards, 6,380 total |
| 8 | Card data extraction | CardDefinition layout: cardId string at +0x10, premium at +0x14 |
| 9 | Deck class discovery (snapshot) | 410 classes found; DeckRule, DeckDetailsDataModel, TwistHeroicDeckDataModel mapped |
| 10 | (reserved) | — |
| 11 | Enhanced diagnostics | ScanLog system, consistency testing |
| 12 | **Trial card probe** | Full CardStack hex dump (+0x00 to +0x3F); identified +0x18 as acquisition timestamp |
| 13 | **Trial timestamp analysis** | Confirmed FILETIME at +0x18; largest group = 1421 Core/trial grants; set cross-reference |
