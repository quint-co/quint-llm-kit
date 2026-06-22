# Quint Language Constraints

**CRITICAL**: These are fundamental limitations of the Quint language. Violating these constraints will result in compilation errors that cannot be worked around.

## Contents

- [1. No String Manipulation](#1-no-string-manipulation)
- [2. No Nested Pattern Matching](#2-no-nested-pattern-matching)
- [3. No Destructuring](#3-no-destructuring)
- [4. No Mutable Local Variables](#4-no-mutable-local-variables)
- [5. No Loops](#5-no-loops)
- [6. No Early Returns](#6-no-early-returns)
- [7. Type Inference Limitations](#7-type-inference-limitations)
- [Debugging Workflow](#debugging-workflow)

---

## 1. No String Manipulation

Quint treats strings as **opaque values** — equality comparison only.

```quint
// ❌ NOT allowed
"hello" + "world"        // concatenation
"value: ${x}"           // interpolation
str[0]                  // indexing
str.length()            // methods
toString(42)            // conversion

// ✅ Allowed
name == "Alice"         // equality comparison
Map("a" -> 1)           // strings as map keys
Set("alice", "bob")     // strings in sets
```

When you need composite identifiers, use records or sum types instead:

```quint
// Instead of string concatenation, use structured data
type MessageId = { sender: str, round: int }
```

---

## 2. No Nested Pattern Matching

`match` works on **one level only**. Nested patterns cause a compile error.

```quint
// ❌ NOT allowed — nested patterns
match msg
  | Request(Prepare(n, v)) => ...

// ✅ Allowed — sequential matches
match msg
  | Request(inner) =>
      match inner
        | Prepare(n, v) => ...
        | Promise(n, r) => ...
```

**Rule**: Match one layer at a time. Use intermediate `val` bindings between match levels.

---

## 3. No Destructuring

You cannot unpack tuples or records in binding positions.

```quint
// ❌ NOT allowed
val (x, y) = get_pair()       // tuple destructuring
val { name, age } = person    // record destructuring
def f((a, b)) = a + b         // parameter destructuring

// ✅ Allowed — explicit field access
val pair = get_pair()
val x = pair._1
val y = pair._2

val person_name = person.name
def f(p) = p._1 + p._2

// ✅ Allowed — match for sum types
val value = match optional
  | Some(v) => v
  | None    => default_value
```

---

## 4. No Mutable Local Variables

`val` bindings are immutable. You cannot reassign within a definition.

```quint
// ❌ NOT allowed
val x = 1
val x = 2   // redeclaration error

// ✅ Use state variables (with ') for mutable state across transitions
// ✅ Use if-then-else or match for conditional values
```

---

## 5. No Loops

Quint has no `for` or `while`. Use set/list/map operators instead.

```quint
// ❌ NOT a thing in Quint
for x in S: x + 1

// ✅ Use functional operators
S.map(x => x + 1)
S.fold(0, (acc, x) => acc + x)
S.filter(x => x > 0)
```

---

## 6. No Early Returns

Definitions must have a **single expression** as their body.

```quint
// ❌ NOT allowed
pure def f(x: int): int = {
  if (x < 0) return -1   // no return keyword
  x + 1
}

// ✅ Use if-then-else
pure def f(x: int): int =
  if (x < 0) -1 else x + 1

// ✅ Use match for multiple cases
pure def classify(x: int): str =
  if (x < 0) "negative"
  else if (x == 0) "zero"
  else "positive"
```

---

## 7. Type Inference Limitations

Quint infers types well, but needs help with empty collections and polymorphic operators.

```quint
// ❌ Ambiguous — type of empty set unknown
val s = Set()

// ✅ Provide context
val s: Set[int] = Set()
// or just start with elements
val s = Set(1, 2, 3)
```

---

## Debugging Workflow

When you hit a compilation error:

1. **Check constraints first** — most errors come from the seven rules above
2. **Read the error message** — the type checker is precise about location and cause
3. **Break complex expressions into `val` steps** — simplifies type inference and debugging
4. **Match one level at a time** — never nest patterns
5. **Use explicit field access** — `.field`, `._1`, `._2` instead of destructuring
