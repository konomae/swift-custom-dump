/// Detects differences between two given values by comparing their mirrors and optionally returns
/// a formatted string describing it.
///
/// This can be a great tool to use for building debug tools for applications and libraries. For
/// example, this library uses ``diff(_:_:format:)`` to implement
/// ``XCTAssertNoDifference(_:_:_:file:line:)``, which asserts that two values are equal, and
/// if they are not the failure message is a nicely formatted diff showing exactly what part of the
/// values are not equal.
///
/// Further, the
/// [Composable Architecture](https://www.github.com/pointfreeco/swift-composable-architecture) uses
/// ``diff(_:_:format:)`` in a couple different ways:
///
/// * It is used to implement a tool that prints changes to application state over time as diffs
///   between the previous state and the current state whenever an action is sent to the store.
/// * It is also used in a testing tool so that when one fails to assert for how state may have
///   changed after sending an action, it can display a concise message showing the exact difference
///   in state.
///
/// - Parameters:
///   - lhs: An expression of type `T`.
///   - rhs: A second expression of type `T`.
///   - format: A format to use for the diff. By default it uses ASCII characters typically
///     associated with the "diff" format: "-" for removals, "+" for additions, and " " for
///     unchanged lines.
/// - Returns: A string describing any difference detected between values, or `nil` if no difference
///   is detected.
public func diff<T>(_ lhs: T, _ rhs: T, format: DiffFormat = .default) -> String? {
  var visitedItems: Set<ObjectIdentifier> = []

  func diffHelp(
    _ lhs: Any,
    _ rhs: Any,
    lhsName: String?,
    rhsName: String?,
    separator: String,
    indent: Int
  ) -> String {
    let rhsName = rhsName ?? lhsName
    guard !isMirrorEqual(lhs, rhs) else {
      return _customDump(lhs, name: rhsName, indent: indent, maxDepth: 0)
        .appending(separator)
        .indenting(with: format.both + " ")
    }

    let lhsMirror = Mirror(customDumpReflecting: lhs)
    let rhsMirror = Mirror(customDumpReflecting: rhs)
    var out = ""

    func diffEverything() {
      print(
        _customDump(lhs, name: lhsName, indent: indent, maxDepth: .max)
          .appending(separator)
          .indenting(with: format.first + " "),
        to: &out
      )
      print(
        _customDump(rhs, name: rhsName, indent: indent, maxDepth: .max)
          .appending(separator)
          .indenting(with: format.second + " "),
        terminator: "",
        to: &out
      )
    }

    guard lhsMirror.subjectType == rhsMirror.subjectType
    else {
      diffEverything()
      return out
    }

    func diffChildren(
      _ lhsMirror: Mirror,
      _ rhsMirror: Mirror,
      prefix: String,
      suffix: String,
      elementIndent: Int,
      elementSeparator: String,
      collapseUnchanged: Bool,
      areEquivalent: (Mirror.Child, Mirror.Child) -> Bool = { $0.label == $1.label },
      areInIncreasingOrder: ((Mirror.Child, Mirror.Child) -> Bool)? = nil,
      _ transform: (inout Mirror.Child, Int) -> Void = { _, _ in }
    ) {
      guard !lhsMirror.children.isEmpty || !rhsMirror.children.isEmpty
      else {
        print(
          _customDump(
            lhs,
            name: lhsName,
            indent: indent,
            maxDepth: 0
          )
          .indenting(with: format.first + " "),
          to: &out
        )
        print(
          _customDump(
            rhs,
            name: rhsName,
            indent: indent,
            maxDepth: 0
          )
          .indenting(with: format.second + " "),
          terminator: "",
          to: &out
        )
        return
      }

      guard !lhsMirror.isSingleValueContainer && !rhsMirror.isSingleValueContainer
      else {
        print(
          _customDump(
            lhs,
            name: lhsName,
            indent: indent,
            maxDepth: .max
          )
          .indenting(with: format.first + " "),
          to: &out
        )
        print(
          _customDump(
            rhs,
            name: rhsName,
            indent: indent,
            maxDepth: .max
          )
          .indenting(with: format.second + " "),
          terminator: "",
          to: &out
        )
        return
      }

      let name = rhsName.map { "\($0): " } ?? ""
      print(
        name
          .appending(prefix)
          .indenting(by: indent)
          .indenting(with: format.both + " "),
        to: &out
      )

      var lhsChildren = Array(lhsMirror.children)
      var rhsChildren = Array(rhsMirror.children)

      if let areInIncreasingOrder = areInIncreasingOrder {
        lhsChildren.sort(by: areInIncreasingOrder)
        rhsChildren.sort(by: areInIncreasingOrder)
      }

      let difference = rhsChildren.difference(from: lhsChildren, by: areEquivalent)

      var lhsOffset = 0
      var rhsOffset = 0
      var unchangedBuffer: [Mirror.Child] = []

      func flushUnchanged() {
        guard collapseUnchanged else { return }
        if areInIncreasingOrder == nil && unchangedBuffer.count == 1 {
          let child = unchangedBuffer[0]
          print(
            _customDump(
              child.value,
              name: child.label,
              indent: indent + elementIndent,
              maxDepth: 0
            )
            .indenting(with: format.both + " "),
            terminator: rhsOffset - 1 == rhsChildren.count - 1 ? "\n" : "\(elementSeparator)\n",
            to: &out
          )
        } else if areInIncreasingOrder != nil && unchangedBuffer.count == 1
          || unchangedBuffer.count > 1
        {
          print(
            "… (\(unchangedBuffer.count) unchanged)"
              .indenting(by: indent + elementIndent)
              .indenting(with: format.both + " "),
            terminator: rhsOffset - 1 == rhsChildren.count - 1 ? "\n" : "\(elementSeparator)\n",
            to: &out
          )
        }
        unchangedBuffer.removeAll()
      }

      while lhsOffset < lhsChildren.count || rhsOffset < rhsChildren.count {
        let isRemoval = difference.removals.contains(where: { $0.offset == lhsOffset })
        let isInsertion = difference.insertions.contains(where: { $0.offset == rhsOffset })

        if collapseUnchanged,
          !isRemoval,
          !isInsertion,
          isMirrorEqual(lhsChildren[lhsOffset], rhsChildren[rhsOffset])
        {
          var child = rhsChildren[rhsOffset]
          transform(&child, rhsOffset)
          unchangedBuffer.append(child)
          lhsOffset += 1
          rhsOffset += 1
          continue
        }

        if areInIncreasingOrder == nil {
          flushUnchanged()
        }

        switch (isRemoval, isInsertion) {
        case (true, true), (false, false):
          var lhsChild = lhsChildren[lhsOffset]
          var rhsChild = rhsChildren[rhsOffset]
          transform(&lhsChild, isRemoval ? lhsOffset : rhsOffset)
          transform(&rhsChild, rhsOffset)
          print(
            diffHelp(
              lhsChild.value,
              rhsChild.value,
              lhsName: lhsChild.label,
              rhsName: rhsChild.label,
              separator: lhsOffset == lhsChildren.count - 1 && rhsOffset == rhsChildren.count - 1
                ? ""
                : elementSeparator,
              indent: indent + elementIndent
            ),
            to: &out
          )
          lhsOffset += 1
          rhsOffset += 1
          continue

        case (true, false):
          var lhsChild = lhsChildren[lhsOffset]
          transform(&lhsChild, lhsOffset)
          print(
            _customDump(
              lhsChild.value,
              name: lhsChild.label,
              indent: indent + elementIndent,
              maxDepth: .max
            )
            .indenting(with: format.first + " "),
            terminator: lhsOffset == lhsChildren.count - 1 ? "\n" : "\(elementSeparator)\n",
            to: &out
          )
          lhsOffset += 1

        case (false, true):
          var rhsChild = rhsChildren[rhsOffset]
          transform(&rhsChild, rhsOffset)
          print(
            _customDump(
              rhsChild.value,
              name: rhsChild.label,
              indent: indent + elementIndent,
              maxDepth: .max
            )
            .indenting(with: format.second + " "),
            terminator: rhsOffset == rhsChildren.count - 1 && unchangedBuffer.isEmpty
              ? "\n"
              : "\(elementSeparator)\n",
            to: &out
          )
          rhsOffset += 1
        }
      }

      flushUnchanged()

      print(
        suffix
          .indenting(by: indent)
          .indenting(with: format.both + " "),
        terminator: separator,
        to: &out
      )
    }

    switch (lhs, lhsMirror.displayStyle, rhs, rhsMirror.displayStyle) {
    case (is CustomDumpStringConvertible, _, is CustomDumpStringConvertible, _):
      diffEverything()

    case let (lhs as CustomDumpRepresentable, _, rhs as CustomDumpRepresentable, _):
      out.write(
        diffHelp(
          lhs.customDumpValue,
          rhs.customDumpValue,
          lhsName: lhsName,
          rhsName: rhsName,
          separator: separator,
          indent: indent
        )
      )

    case let (lhs as AnyObject, .class?, rhs as AnyObject, .class?):
      let lhsItem = ObjectIdentifier(lhs)
      let rhsItem = ObjectIdentifier(rhs)
      let subjectType = typeName(lhsMirror.subjectType)
      if visitedItems.contains(lhsItem) || visitedItems.contains(rhsItem) {
        print(
          "\(subjectType)(↩︎)"
            .indenting(by: indent)
            .indenting(with: format.first + " "),
          to: &out
        )
        print(
          "\(subjectType)(↩︎)"
            .indenting(by: indent)
            .indenting(with: format.second + " "),
          terminator: "",
          to: &out
        )
      } else {
        visitedItems.insert(lhsItem)
        diffChildren(
          lhsMirror,
          rhsMirror,
          prefix: "\(subjectType)(",
          suffix: ")",
          elementIndent: 2,
          elementSeparator: ",",
          collapseUnchanged: false
        )
      }

    case (_, .collection?, _, .collection?):
      diffChildren(
        lhsMirror,
        rhsMirror,
        prefix: "[",
        suffix: "]",
        elementIndent: 2,
        elementSeparator: ",",
        collapseUnchanged: true,
        areEquivalent: {
          isIdentityEqual($0.value, $1.value) || isMirrorEqual($0.value, $1.value)
        },
        { $0.label = "[\($1)]" }
      )

    case (_, .dictionary?, _, .dictionary?):
      diffChildren(
        lhsMirror,
        rhsMirror,
        prefix: "[",
        suffix: "]",
        elementIndent: 2,
        elementSeparator: ",",
        collapseUnchanged: true,
        areEquivalent: {
          guard
            let lhs = $0.value as? (key: AnyHashable, value: Any),
            let rhs = $1.value as? (key: AnyHashable, value: Any)
          else {
            return isMirrorEqual($0.value, $1.value)
          }
          return lhs.key == rhs.key
        },
        areInIncreasingOrder: {
          guard
            let lhs = $0.value as? (key: AnyHashable, value: Any),
            let rhs = $1.value as? (key: AnyHashable, value: Any)
          else {
            return _customDump($0.value, name: nil, indent: 0, maxDepth: 1)
              < _customDump($1.value, name: nil, indent: 0, maxDepth: 1)
          }
          return _customDump(lhs.key.base, name: nil, indent: 0, maxDepth: 1)
            < _customDump(rhs.key.base, name: nil, indent: 0, maxDepth: 1)
        }
      ) { child, _ in
        guard let pair = child.value as? (key: AnyHashable, value: Any) else { return }
        child = (
          _customDump(pair.key.base, name: nil, indent: 0, maxDepth: 1),
          pair.value
        )
      }

    case (_, .enum?, _, .enum?):
      guard
        let lhsChild = lhsMirror.children.first,
        let rhsChild = rhsMirror.children.first,
        let caseName = lhsChild.label,
        caseName == rhsChild.label
      else {
        diffEverything()
        break
      }
      let lhsChildMirror = Mirror(customDumpReflecting: lhsChild.value)
      let rhsChildMirror = Mirror(customDumpReflecting: rhsChild.value)
      let lhsAssociatedValuesMirror =
        lhsChildMirror.displayStyle == .tuple
        ? lhsChildMirror
        : Mirror(lhs, unlabeledChildren: [lhsChild.value], displayStyle: .tuple)
      let rhsAssociatedValuesMirror =
        rhsChildMirror.displayStyle == .tuple
        ? rhsChildMirror
        : Mirror(rhs, unlabeledChildren: [rhsChild.value], displayStyle: .tuple)

      let subjectType = typeName(lhsMirror.subjectType)
      diffChildren(
        lhsAssociatedValuesMirror,
        rhsAssociatedValuesMirror,
        prefix: "\(subjectType).\(caseName)(",
        suffix: ")",
        elementIndent: 2,
        elementSeparator: ",",
        collapseUnchanged: false,
        { child, _ in
          if child.label?.first == "." {
            child.label = nil
          }
        }
      )

    case (_, .optional?, _, .optional?):
      guard
        let lhsValue = lhsMirror.children.first?.value,
        let rhsValue = rhsMirror.children.first?.value
      else {
        diffEverything()
        break
      }

      out.write(
        diffHelp(
          lhsValue,
          rhsValue,
          lhsName: lhsName,
          rhsName: rhsName,
          separator: separator,
          indent: indent
        )
      )

    case (_, .set?, _, .set?):
      diffChildren(
        lhsMirror,
        rhsMirror,
        prefix: "Set([",
        suffix: "])",
        elementIndent: 2,
        elementSeparator: ",",
        collapseUnchanged: true,
        areEquivalent: {
          isIdentityEqual($0.value, $1.value) || isMirrorEqual($0.value, $1.value)
        },
        areInIncreasingOrder: {
          _customDump($0.value, name: nil, indent: 0, maxDepth: 1)
            < _customDump($1.value, name: nil, indent: 0, maxDepth: 1)
        }
      )

    case (_, .struct?, _, .struct?):
      diffChildren(
        lhsMirror,
        rhsMirror,
        prefix: "\(typeName(lhsMirror.subjectType))(",
        suffix: ")",
        elementIndent: 2,
        elementSeparator: ",",
        collapseUnchanged: false
      )

    case (_, .tuple?, _, .tuple?):
      diffChildren(
        lhsMirror,
        rhsMirror,
        prefix: "(",
        suffix: ")",
        elementIndent: 2,
        elementSeparator: ",",
        collapseUnchanged: false,
        { child, _ in
          if child.label?.first == "." {
            child.label = nil
          }
        }
      )

    default:
      if let lhs = stringFromStringProtocol(lhs),
        let rhs = stringFromStringProtocol(rhs),
        lhs.contains(where: \.isNewline) || rhs.contains(where: \.isNewline)
      {
        let lhsMirror = Mirror(
          customDumpReflecting:
            lhs.isEmpty
            ? []
            : lhs
              .split(separator: "\n", omittingEmptySubsequences: false)
              .map(Line.init(rawValue:))
        )
        let rhsMirror = Mirror(
          customDumpReflecting:
            rhs.isEmpty
            ? []
            : rhs
              .split(separator: "\n", omittingEmptySubsequences: false)
              .map(Line.init(rawValue:))
        )
        let hashes = String(repeating: "#", count: max(lhs.hashCount, rhs.hashCount))
        diffChildren(
          lhsMirror,
          rhsMirror,
          prefix: "\(hashes)\"\"\"",
          suffix: rhsName != nil ? "  \"\"\"\(hashes)" : "\"\"\"\(hashes)",
          elementIndent: rhsName != nil ? 2 : 0,
          elementSeparator: "",
          collapseUnchanged: false,
          areEquivalent: {
            isIdentityEqual($0.value, $1.value) || isMirrorEqual($0.value, $1.value)
          }
        )
      } else {
        diffEverything()
      }
    }

    return out
  }

  guard !isMirrorEqual(lhs, rhs) else { return nil }

  var diff = diffHelp(lhs, rhs, lhsName: nil, rhsName: nil, separator: "", indent: 0)
  if diff.last == "\n" { diff.removeLast() }
  return diff
}

/// Describes how to format a difference between two values when using ``diff(_:_:format:)``.
///
/// Typically one simply wants to use "-" to denote removals, "+" to denote additions, and " " for
/// spacing. However, in some contexts, such as in `XCTest` failures, messages are displayed in a
/// non-monospaced font. In those times the simple "-" and " " characters do not properly line up
/// visually, and so you need to use different characters that visually look similar to "-" and " "
/// but have the proper widths.
///
/// This type comes with two pre-configured formats that you will probably want to use for most
/// situations: ``DiffFormat/default`` and ``DiffFormat/proportional``.
public struct DiffFormat {
  /// A string prepended to lines that only appear in the string representation of the first value,
  /// e.g. a "removal."
  public var first: String

  /// A string prepended to lines that only appear in the string representation of the second value,
  /// e.g. an "insertion."
  public var second: String

  /// A string prepended to lines that appear in the string representation of both values, e.g.
  /// something "unchanged."
  public var both: String

  public init(
    first: String,
    second: String,
    both: String
  ) {
    self.first = first
    self.second = second
    self.both = both
  }

  /// The default format for ``diff(_:_:format:)`` output, appropriate for where monospaced fonts
  /// are used, e.g. console output.
  ///
  /// Uses ascii characters for removals (hyphen "-"), insertions (plus "+"), and unchanged (space
  /// " ").
  public static let `default` = Self(first: "-", second: "+", both: " ")

  /// A diff format appropriate for where proportional (non-monospaced) fonts are used, e.g. Xcode's
  /// failure overlays.
  ///
  /// Uses ascii plus ("+") for insertions, unicode minus sign ("−") for removals, and unicode
  /// figure space (" ") for unchanged. These three characters are more likely to render with equal
  /// widths in proportional fonts.
  public static let proportional = Self(first: "\u{2212}", second: "+", both: "\u{2007}")
}

private struct Line: CustomDumpStringConvertible, Identifiable {
  var rawValue: Substring

  var id: Substring {
    self.rawValue
  }

  var customDumpDescription: String {
    .init(self.rawValue)
  }
}
