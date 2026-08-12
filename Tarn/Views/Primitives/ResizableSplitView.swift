//
//  ResizableSplitView.swift
//  Tarn
//
//  Created by ghazi on 12/17/25.
//

import AppKit
import SwiftUI

struct ResizableSplitView<Left: View, Right: View>: NSViewControllerRepresentable {
  let leftView: Left
  let rightView: Right
  let minLeftWidth: CGFloat
  let minRightWidth: CGFloat
  let idealLeftWidth: CGFloat?
  let idealRightWidth: CGFloat?
  let maxLeftWidth: CGFloat?

  init(
    minLeftWidth: CGFloat = 150,
    minRightWidth: CGFloat = 200,
    idealLeftWidth: CGFloat? = nil,
    idealRightWidth: CGFloat? = nil,
    maxLeftWidth: CGFloat? = nil,
    @ViewBuilder left: () -> Left,
    @ViewBuilder right: () -> Right
  ) {
    self.minLeftWidth = minLeftWidth
    self.minRightWidth = minRightWidth
    self.idealLeftWidth = idealLeftWidth
    self.idealRightWidth = idealRightWidth
    self.maxLeftWidth = maxLeftWidth
    self.leftView = left()
    self.rightView = right()
  }

  func makeNSViewController(context: Context) -> NSSplitViewController {
    let splitViewController = NSSplitViewController()

    // Left view controller
    let leftViewController = NSHostingController(rootView: leftView)
    let leftItem = NSSplitViewItem(viewController: leftViewController)
    leftItem.minimumThickness = minLeftWidth
    if let maxLeftWidth = maxLeftWidth {
      leftItem.maximumThickness = maxLeftWidth
    }
    if let idealLeftWidth = idealLeftWidth {
      // Calculate fraction based on ideal widths if both are provided
      if let idealRightWidth = idealRightWidth {
        let totalIdeal = idealLeftWidth + idealRightWidth
        leftItem.preferredThicknessFraction = idealLeftWidth / totalIdeal
      } else {
        leftItem.preferredThicknessFraction = 0.25  // Default fraction if only left ideal is set
      }
    } else {
      leftItem.preferredThicknessFraction = 0.25  // Default: left panel takes 25% of space
    }
    splitViewController.addSplitViewItem(leftItem)

    // Right view controller
    let rightViewController = NSHostingController(rootView: rightView)
    let rightItem = NSSplitViewItem(viewController: rightViewController)
    rightItem.minimumThickness = minRightWidth
    if let idealRightWidth = idealRightWidth {
      // Calculate fraction based on ideal widths if both are provided
      if let idealLeftWidth = idealLeftWidth {
        let totalIdeal = idealLeftWidth + idealRightWidth
        rightItem.preferredThicknessFraction = idealRightWidth / totalIdeal
      } else {
        rightItem.preferredThicknessFraction = 0.75  // Default fraction if only right ideal is set
      }
    } else {
      rightItem.preferredThicknessFraction = 0.75  // Default: right panel takes 75% of space
    }
    splitViewController.addSplitViewItem(rightItem)

    // Configure split view
    splitViewController.splitView.dividerStyle = .thin
    splitViewController.splitView.isVertical = true

    return splitViewController
  }

  func updateNSViewController(_ nsViewController: NSSplitViewController, context: Context) {
    // Update if needed
  }
}

