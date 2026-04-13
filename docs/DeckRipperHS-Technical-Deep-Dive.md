# DeckRipperHS: Reading Hearthstone's Card Collection from Process Memory

### A Technical Deep Dive into Runtime Memory Introspection of a Unity/Mono Game

**Authors:** Claude (Anthropic) & Brian G.  
**Date:** April 8, 2026  
**Project:** DeckRipperHS — macOS agent for the Hearthstone Deck Builder

---

## Preface

This document describes how we built, from scratch and without referencing any existing implementation, a tool that reads a Hearthstone player's complete card collection directly from the game's process memory on macOS. No third-party frameworks, no reverse-engineering tools, no disassemblers — just first-principles reasoning about how the Mono runtime organizes objects in memory, validated through iterative diagnostic probing of a live game process.

The entire process — from "can we even do this?" to a working extraction of 3,564 cards — took place in a single collaborative session.

---

## 1. The Problem

Hearthstone players who want to use deck-building tools need to export their card collection. The standard method requires logging into HSReplay.net, opening browser DevTools, navigating to the Network tab, filtering for the `collection` API call, and copying raw JSON. This is a terrible user experience for non-technical players.

The macOS app HSTracker solves this by reading Hearthstone's memory using a closed-source framework called HearthMirror. We wanted to build our own reader — independent, open, and fully understood.

---

## 2. The Approach: Why Memory Reading Works

Hearthstone is built on the **Unity game engine**, which embeds the **Mono runtime** — an open-source implementation of the .NET Common Language Runtime. This means all of Hearthstone's game logic (written in C#) runs inside a Mono virtual machine, and all game objects — including the player's card collection — exist as Mono-managed objects on the heap.

On macOS, any process with sufficient privileges can read another process's memory using the **Mach microkernel APIs**:

- `task_for_pid()` — obtain a task port for the target process
- `mach_vm_read()` — read arbitrary memory from the target's address space
- `mach_vm_region()` — enumerate the target's memory regions

These are kernel-level operations invisible to the target process. Hearthstone cannot detect that we are reading its memory — there are no page faults, no system events, no network traffic. It is a completely passive, read-only operation on the user's own machine.

---

## 3. The Challenge: Finding a Needle in a Haystack

Hearthstone's process occupies **gigabytes** of virtual memory. The card collection is a single object somewhere in that space. We had no symbols, no debug information, no documentation of the Mono struct layouts for this specific Unity version. We knew three things:

1. Mono uses well-known internal data structures (MonoDomain, MonoAssembly, MonoImage, MonoClass) to organize loaded code
2. Hearthstone's card collection lives in a C# class called `NetCacheCollection`
3. The collection contains objects called `CardStack` with card identifiers and counts

Everything else had to be discovered.

---

## 4. The Iterative Discovery Process

### Phase 1: Finding the Mono Root Domain

Every Mono runtime has a **root domain** — the entry point that holds references to all loaded assemblies. We found it by scanning memory regions for the characteristic pattern of a domain structure: a pointer at a known offset that leads to a linked list of assemblies with readable names like `"mscorlib"` and `"Assembly-CSharp"`.

**Result:** Root domain found at `0x122eaed08`. We confirmed it by reading the assembly list — 103 loaded assemblies including `Assembly-CSharp` (Hearthstone's game code), various `Blizzard.T5.*` modules, Unity engine modules, and standard .NET libraries.

### Phase 2: Mapping the MonoImage Structure

We located the `Assembly-CSharp` image (the compiled DLL metadata loaded into memory) and dumped its structure byte-by-byte. Key findings:

| Offset | Content |
|--------|---------|
| +0x20 | Full DLL path: `/Applications/Hearthstone/Hearthstone.app/.../Assembly-CSharp.dll` |
| +0x30 | Assembly name: `"Assembly-CSharp"` |
| +0x38 | Filename: `"Assembly-CSharp.dll"` |
| +0x48 | Runtime version: `"v4.0.30319"` |
| +0x70 | PE metadata signature: `"BSJB"` |

We attempted to find the class cache hash table (where Mono stores loaded classes) at the offsets documented for standard Mono builds. **It wasn't there.** This version of Unity uses a modified Mono with different internal layouts. The class cache scan found zero candidates across the entire image structure.

This was our first dead end — and the point where brute-force documentation-based approaches fail.

### Phase 3: Direct String Scanning

Instead of navigating Mono's metadata structures top-down, we went bottom-up. We scanned all of Hearthstone's memory for the literal string `"NetCacheCollection"` (null-terminated), then searched for any pointer-aligned 8-byte value pointing to that string address.

For each such pointer, we checked whether it could be the `name` field of a `MonoClass` structure by looking at surrounding memory. We found:

**NetCacheCollection MonoClass at `0x7fa628515958`**

By examining the structure around it, we determined the actual field layout for this Mono version:

| MonoClass Offset | Content |
|-----------------|---------|
| +0x00 | Internal flags: `0x0000002801000002` |
| +0x18 | Parent class pointer |
| +0x20 | **Image pointer** (matched Assembly-CSharp) |
| +0x28 | **Class name pointer** → `"NetCacheCollection"` |
| +0x30 | **Namespace pointer** → `""` (empty) |
| +0xF8 | Field name → `"<Stacks>k__BackingField"` |
| +0x118 | Field name → `"TotalCardsOwned"` |

This was a critical breakthrough — the class name is at **+0x28** (not +0x30 as in standard Mono documentation), and field descriptors are visible inline in the class structure.

### Phase 4: Reading the Parent Class

The parent class at +0x18 had a **different layout** — its name was at +0x40 instead of +0x28. This is because the parent structure has self-referential `element_class` and `cast_class` pointers at +0x00 and +0x08 that shift everything down. We confirmed the parent was `"NetCache"` — the singleton manager class that holds the collection.

### Phase 5: Extracting Instance Field Offsets

The field descriptor area near the end of the MonoClass structure revealed the **instance field offsets** — the byte positions within a live NetCacheCollection object where each field's value is stored:

| Field | Instance Offset | Type |
|-------|----------------|------|
| `<Stacks>k__BackingField` | **+0x10** | `List<CardStack>` |
| `CoreCardsUnlockedPerClass` | **+0x18** | `Map<K,V>` |
| `TotalCardsOwned` | **+0x20** | `int32` |

These offsets were determined by reading the int32 value at `fieldDescriptor + 0x10`, which consistently yielded `16`, `24`, and `32` (0x10, 0x18, 0x20) — the byte offsets within an instance.

### Phase 6: Finding the Live Instance

We now knew what a NetCacheCollection instance looks like in memory, but we still needed to find the actual live instance on the heap. Traditional approaches (walking from the root domain through vtables to static fields) had failed because this Mono version's vtable layout didn't match any documented pattern.

We took a different approach: **pattern-based heap scanning**. We scanned all read-write memory regions for 8-byte-aligned locations matching this fingerprint:

```
+0x00: valid pointer (vtable)
+0x10: valid pointer → object whose class name contains "List"
+0x18: valid pointer → not a packed int32 pair
+0x20: int32 in range [200, 20000] with upper 32 bits = 0
```

Additional validation:
- The List object at +0x10 must have a `_size` field (at List+0x18) between 100 and 50,000
- The object's class name (resolved through its vtable) must equal `"NetCacheCollection"`

**Result:** Exactly one match across the entire heap:

```
NetCacheCollection at 0x0000000175026360
TotalCardsOwned:  6380
Stacks:           List`1 with 3,564 entries
CoreCards:        Map`2
```

### Phase 7: Reading Card Data

The Stacks list is a standard Mono `List<T>`:
- +0x10: `_items` — pointer to the backing array
- +0x18: `_size` — number of valid entries (3,564)

The backing array uses standard Mono array layout:
- +0x10: array length (4,096 — capacity, not count)
- +0x20: first element pointer (8 bytes per element)

Each element is a **CardStack** object:

| CardStack Offset | Content |
|-----------------|---------|
| +0x00 | vtable → CardStack class |
| +0x10 | **CardDefinition pointer** |
| +0x20 | **Count** (int32 — copies owned) |
| +0x24 | NumSeen (int32 — equals Count) |

Each **CardDefinition** object:

| CardDefinition Offset | Content |
|----------------------|---------|
| +0x00 | vtable → CardDefinition class |
| +0x10 | **Card ID** (Mono string — e.g., `"EX1_055"`) |
| +0x14 | **Premium flag** (int32 — 1=normal) |

The card ID is a Mono string object (UTF-16LE encoded, length at +0x10, characters at +0x14).

### Phase 8: Full Extraction

With all offsets confirmed, the extraction reads all 3,564 CardStack entries and outputs:

```json
{
  "agentId": "71482858-c91c-49a8-ae9f-dfe848f4a4e7",
  "cards": [
    { "cardId": "EX1_055", "count": 2, "premium": 1 },
    { "cardId": "EX1_607", "count": 2, "premium": 1 },
    { "cardId": "EX1_339", "count": 2, "premium": 1 },
    { "cardId": "NEW1_010", "count": 1, "premium": 1 },
    ...
  ],
  "totalCardsOwned": 6380,
  "uniqueEntries": 3564
}
```

Every card ID corresponds to a real Hearthstone card. Classic cards (EX1_*), Lich King expansion cards (RLK_*), and everything in between — all correctly extracted with accurate copy counts.

---

## 5. Complete Memory Map

```
Hearthstone Process Memory
│
├── Mono Root Domain (0x122eaed08)
│   └── domain_assemblies (+0xC8) → GSList of MonoAssembly
│       ├── mscorlib
│       ├── UnityEngine.*
│       ├── Assembly-CSharp (0x60000223b180)
│       │   └── image (+0x60) → MonoImage (0x7fa606948a00)
│       │       ├── name (+0x30) → "Assembly-CSharp"
│       │       ├── filename (+0x38) → "Assembly-CSharp.dll"
│       │       └── [class cache at non-standard offset]
│       └── Blizzard.T5.*, System.*, etc.
│
├── MonoClass: NetCacheCollection (0x7fa628515958)
│   ├── name (+0x28) → "NetCacheCollection"
│   ├── namespace (+0x30) → ""
│   ├── image (+0x20) → Assembly-CSharp image
│   ├── parent (+0x18) → NetCache class (name at parent+0x40)
│   └── field descriptors:
│       ├── Stacks → instance offset 0x10
│       ├── CoreCardsUnlockedPerClass → instance offset 0x18
│       └── TotalCardsOwned → instance offset 0x20
│
├── Live NetCacheCollection Instance (0x175026360)  [HEAP]
│   ├── vtable (+0x00) → identifies as NetCacheCollection
│   ├── Stacks (+0x10) → List`1 (0x...)
│   │   ├── _items (+0x10) → CardStack[] array
│   │   │   ├── [0] → CardStack (0x175026270)
│   │   │   │   ├── CardDefinition (+0x10) → (0x175026240)
│   │   │   │   │   ├── CardID (+0x10) → MonoString "EX1_055"
│   │   │   │   │   └── Premium (+0x14) → 1 (normal)
│   │   │   │   └── Count (+0x20) → 2
│   │   │   ├── [1] → CardStack → "EX1_607" x2
│   │   │   ├── [2] → CardStack → "EX1_339" x2
│   │   │   └── ... (3,564 entries)
│   │   └── _size (+0x18) → 3564
│   ├── CoreCardsUnlockedPerClass (+0x18) → Map`2
│   └── TotalCardsOwned (+0x20) → 6380
```

---

## 6. Technical Decisions and Why They Mattered

### Why top-down navigation failed

The standard approach to reading Mono objects is: root domain → assembly → image → class cache → class → vtable → static fields → singleton instance. This failed at two points:

1. **The class cache** was not at the documented offset (+0x170) in MonoImage. This Mono version (embedded in Unity for Hearthstone) uses a modified layout. Scanning the entire image structure for hash-table-like patterns found nothing.

2. **The vtable** did not contain a back-pointer to its class at any of the documented offsets. The standard pattern of `vtable.klass → MonoClass` was not present, or used an offset outside our scan range.

### Why bottom-up pattern matching succeeded

Instead of following the Mono metadata hierarchy, we:

1. Searched raw memory for known strings (`"NetCacheCollection"`)
2. Found structures pointing to those strings (MonoClass objects)
3. Read field metadata directly from the class structure
4. Scanned the heap for objects matching a specific field-value fingerprint

This approach is **resilient to Mono version differences** because it relies on two stable properties:
- String literals in the binary don't move (they're in the constant pool)
- C# field values have predictable types and ranges

### Why we use card ID strings instead of dbfIds

The CardDefinition object stores the **string card ID** (e.g., `"EX1_055"`) rather than the numeric dbfId. While dbfIds would be more convenient, the string IDs are equally authoritative — HearthstoneJSON provides a complete mapping. This also means our extraction is not dependent on finding a secondary numeric field whose offset could vary.

---

## 7. Performance Characteristics

The current implementation performs a full heap scan on every extraction, which takes **1-3 minutes** depending on Hearthstone's memory footprint. This can be optimized:

- **Cache the vtable address** after the first successful find — subsequent extractions skip the scan entirely
- **Cache the instance address** — if Hearthstone hasn't restarted, the object hasn't moved
- **Reduce scan scope** — only scan regions in the heap range, not all readable memory

With caching, extraction should drop to **under 1 second**.

---

## 8. Limitations and Future Work

- **Mono offset sensitivity**: If Blizzard upgrades Unity (and thus the embedded Mono runtime), the MonoClass field layout may shift. The diagnostic tooling we built can rediscover offsets automatically.
- **Collection must be loaded**: The NetCacheCollection object only exists in memory after the game loads the player's collection data (typically on reaching the main menu).
- **macOS only**: This implementation uses Mach APIs specific to macOS. A Windows version would use `ReadProcessMemory` with a similar scanning approach.
- **Requires elevated privileges**: `task_for_pid` needs root access or a debugger entitlement.

---

## 9. Tools and Methods Used

| Tool | Purpose |
|------|---------|
| Swift | Implementation language (native macOS, direct access to Mach APIs) |
| `task_for_pid` | Obtain Mach task port for Hearthstone process |
| `mach_vm_read` | Read arbitrary memory from target process |
| `mach_vm_region` | Enumerate memory regions for scanning |
| Iterative diagnostic probes | 8 rounds of targeted memory analysis |
| Pattern-based heap scanning | Find live objects by field value fingerprinting |

No disassemblers, debuggers, or reverse-engineering tools were used. All analysis was performed through read-only memory inspection and first-principles reasoning about Mono runtime internals.

---

## Acknowledgments

This work was a true collaboration. Brian provided the live Hearthstone environment, domain expertise, and the critical eye that kept the investigation on track ("that number seems high" — it was right). Claude provided the systems knowledge, wrote all code, and designed each diagnostic round based on the results of the previous one.

Neither could have done it alone.

---

*Built with Claude (Anthropic) — April 2026*
