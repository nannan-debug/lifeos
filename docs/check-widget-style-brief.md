# LifeOS Check Widget Style Brief

This document is for an external AI or designer who will redesign the visual style of the LifeOS iOS Home Screen widget. The next engineering step will be to translate the selected design back into SwiftUI.

## Product Context

LifeOS is a gentle personal operating system for capturing daily life, reviewing thoughts, and taking care of small routines without pressure.

The widget being redesigned is the **LifeOS 今日打卡** Home Screen widget. Its job is not to push productivity or judge the user. It should let the user glance at today's check-in items and feel that the day is still manageable.

## Design Goal

Create a distinctive, polished iOS widget style for daily check-ins.

The design should feel:

- Calm, warm, and personal
- Light enough for repeated home-screen viewing
- More refined than a generic beige card
- Friendly without becoming childish
- Useful at a glance, not information-dense

Avoid:

- Streaks
- Completion-rate pressure
- Shame wording
- Alarm-like red warnings
- High-saturation stress colors
- "You failed / you missed / you have not opened the app" framing
- Generic AI gradients, purple-blue SaaS palettes, or decorative blobs

## Current Widget Scope

Only these widget sizes are in scope:

- Small: `systemSmall`
- Medium: `systemMedium`

The widget currently displays daily check-in items. Each item has:

- `title`: the check-in title, for example `吃维生素`
- `done`: whether it is completed today
- `tag`: optional group label, for example `早上`, `晚上`, or empty

The app prioritizes pending items first. If all items are done, it can show completed items.

## Current Copy

You may redesign layout and visual treatment, but keep the tone close to these examples:

- Main title: `今日打卡`
- Pending subtitle: `先照顾这些就好`
- All-done subtitle: `今天已经照顾到了`
- Empty subtitle: `先留一块安静的位置`
- Empty state: `今天可以慢慢来`

If you suggest new copy, it must stay gentle and non-judgmental.

## Existing App Theme References

The app currently uses a soft cream/green theme in SwiftUI:

```swift
bgTop = Color(red: 0.96, green: 0.96, blue: 0.91)
bgBottom = Color(red: 0.93, green: 0.97, blue: 0.92)
text = Color(red: 0.15, green: 0.20, blue: 0.15)
green = Color(red: 0.24, green: 0.65, blue: 0.36)
glass = Color.white.opacity(0.72)
glassStrong = Color.white.opacity(0.82)
border = Color.white.opacity(0.7)
```

The redesign does not need to copy these exactly. It should still feel compatible with a warm, low-pressure LifeOS identity.

## WidgetKit Constraints

The final implementation will be SwiftUI WidgetKit.

Important constraints:

- iOS deployment target is iOS 16.0.
- iOS 17+ widget backgrounds must use `containerBackground(for: .widget)`.
- Avoid interactive controls for this pass. A row can look tappable, but the widget is mainly glanceable.
- Text must fit in both small and medium widgets.
- Use system fonts or SwiftUI-compatible typography unless you clearly specify an Apple-supported fallback.
- The design must work in Light appearance. The current app is Light-only.
- Avoid relying on custom image assets unless you explicitly provide them.
- Avoid tiny text under 10 pt.
- Avoid complex gradients or effects that would be expensive or fragile inside WidgetKit.

## Required States

Please design at least these states:

1. **Small widget with pending items**
   - Title/subtitle
   - Up to 3 check-in rows

2. **Small widget when all visible items are done**
   - Should feel complete, but not celebratory in a loud way

3. **Small widget empty state**
   - No check-in items configured

4. **Medium widget with grouped items**
   - Up to 6 visible rows
   - At most 2 visible groups
   - Group names may be `早上`, `晚上`, `今天`, etc.

5. **Medium widget with mixed done and pending items**
   - Pending should be easy to distinguish from done
   - Done should look settled, not crossed out aggressively

## Design Directions Worth Exploring

Please propose 2-3 distinct directions, not just color variations. Examples:

- **Quiet notebook**: paper texture, ruled structure, soft ink, small tactile marks
- **Morning garden**: organic but restrained, botanical accent, fresh green as a guide color
- **Desk card**: refined physical card, subtle shadow, precise typography, practical grouping

These are suggestions, not requirements. The final direction should be memorable and calm.

## Output Expected From The Designer

Please return:

1. A short rationale for the chosen visual direction.
2. Small and medium widget mockups, preferably with concrete layout descriptions.
3. Color tokens with hex values.
4. Typography choices with size, weight, and line-height guidance.
5. Spacing and corner-radius guidance.
6. Row states for pending and done items.
7. Empty-state treatment.
8. Any SwiftUI implementation notes that would help the engineer.

If visual mockups are not possible, provide a precise component spec that can be implemented directly in SwiftUI.

## Sample Data For Mockups

Use this sample data:

```json
{
  "title": "今日打卡",
  "subtitle": "先照顾这些就好",
  "groups": [
    {
      "title": "早上",
      "items": [
        { "title": "吃维生素", "done": true },
        { "title": "回忆梦境", "done": false }
      ]
    },
    {
      "title": "晚上",
      "items": [
        { "title": "写日记", "done": false },
        { "title": "上床看书", "done": false }
      ]
    }
  ]
}
```

## Acceptance Bar

A good design should pass these checks:

- It is readable on a real iPhone Home Screen.
- It does not look like a generic task widget.
- It does not create guilt, urgency, or productivity pressure.
- It can be implemented in SwiftUI WidgetKit without custom rendering hacks.
- It has clear small and medium variants, not just one layout scaled up.
