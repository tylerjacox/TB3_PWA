// TB3 iOS — Swipe gesture handler for tab navigation
// Uses UIViewControllerRepresentable to attach UISwipeGestureRecognizers
// to a parent view in the UIKit hierarchy, so gestures work alongside
// ScrollView/List/Form without blocking any touches.

import SwiftUI
import UIKit

struct SwipeGestureOverlay: UIViewControllerRepresentable {
    let onSwipeLeft: () -> Void
    let onSwipeRight: () -> Void

    func makeUIViewController(context: Context) -> SwipeGestureViewController {
        let vc = SwipeGestureViewController()
        vc.onSwipeLeft = onSwipeLeft
        vc.onSwipeRight = onSwipeRight
        return vc
    }

    func updateUIViewController(_ uiViewController: SwipeGestureViewController, context: Context) {
        uiViewController.onSwipeLeft = onSwipeLeft
        uiViewController.onSwipeRight = onSwipeRight
    }
}

final class SwipeGestureViewController: UIViewController, UIGestureRecognizerDelegate {
    var onSwipeLeft: (() -> Void)?
    var onSwipeRight: (() -> Void)?

    private var leftGesture: UISwipeGestureRecognizer?
    private var rightGesture: UISwipeGestureRecognizer?
    private weak var attachedView: UIView?

    override func viewDidLoad() {
        super.viewDidLoad()
        // This VC's view sits in the background — make it non-interactive
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Delay slightly to ensure the full view hierarchy is ready
        DispatchQueue.main.async { [weak self] in
            self?.attachGestures()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        detachGestures()
    }

    private func attachGestures() {
        guard attachedView == nil else { return }

        // Find the best view to attach gestures to
        guard let targetView = findTargetView() else { return }

        let left = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        left.direction = .left
        left.delegate = self
        left.cancelsTouchesInView = false
        left.delaysTouchesBegan = false
        left.delaysTouchesEnded = false
        targetView.addGestureRecognizer(left)
        leftGesture = left

        let right = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
        right.direction = .right
        right.delegate = self
        right.cancelsTouchesInView = false
        right.delaysTouchesBegan = false
        right.delaysTouchesEnded = false
        targetView.addGestureRecognizer(right)
        rightGesture = right

        attachedView = targetView
    }

    private func detachGestures() {
        if let left = leftGesture { attachedView?.removeGestureRecognizer(left) }
        if let right = rightGesture { attachedView?.removeGestureRecognizer(right) }
        leftGesture = nil
        rightGesture = nil
        attachedView = nil
    }

    /// Walk up the view hierarchy to find a large parent view that spans the tab content area.
    /// We look for the biggest ancestor before hitting the window, which gives us
    /// the hosting view that contains all SwiftUI content for this tab area.
    private func findTargetView() -> UIView? {
        var best: UIView?
        var candidate = view.superview
        while let v = candidate {
            // Skip the window itself
            if v is UIWindow { break }
            if v.bounds.width > 200 && v.bounds.height > 200 {
                best = v
            }
            candidate = v.superview
        }
        return best ?? parent?.view ?? view.superview
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        switch gesture.direction {
        case .left: onSwipeLeft?()
        case .right: onSwipeRight?()
        default: break
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Always allow simultaneous recognition so scrolling isn't blocked
        return true
    }
}
