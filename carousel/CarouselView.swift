//
//  CarouselView.swift
//  dietbyann
//
//  Created by Paweł Wojtkowiak on 04/03/2021.
//  Copyright © 2021 DietLabs. All rights reserved.
//

import UIKit

public protocol CarouselViewDataSource: class {
    func numberOfItems(in carouselView: CarouselView) -> Int
    func carouselView(_ carouselView: CarouselView, cellForItemAt index: Int) -> UIView
}

public protocol CarouselViewDelegate: class {
    func carouselView(_ carouselView: CarouselView, didScrollToOffset offset: CGFloat)
    func carouselView(_ carouselView: CarouselView, willSnapToItemAt index: Int)
    func carouselView(_ carouselView: CarouselView, didSelectItemAt index: Int)
}

public extension CarouselViewDelegate {
    func carouselView(_ carouselView: CarouselView, didScrollToOffset offset: CGFloat) {}
    func carouselView(_ carouselView: CarouselView, willSnapToItemAt index: Int) {}
    func carouselView(_ carouselView: CarouselView, didSelectItemAt index: Int) {}
}

public final class CarouselView: UIView {
    public enum SnapBehavior {
        /// When scroll is released, snap to next item
        case hard
        
        /// When scroll is released, snap to item that'd be the closest to the scroll destination
        case soft
        
        /// Do not snap
        case none
        
        public static let `default` = SnapBehavior.hard
    }
    
    public struct Transform: Equatable {
        public init(alpha: CGFloat, sizeRatio: CGFloat) {
            self.alpha = alpha
            self.sizeRatio = sizeRatio
        }
        
        public let alpha: CGFloat
        public let sizeRatio: CGFloat
    }
    
    public struct Appearance: Equatable {
        public init(sideItemTransform: CarouselView.Transform = Transform(alpha: 1, sizeRatio: 0.88), centerItemWidthPercentage: CGFloat = 0.63, itemSpacing: CGFloat = 10, additionalInsets: UIEdgeInsets = .zero) {
            self.sideItemTransform = sideItemTransform
            self.centerItemWidthPercentage = centerItemWidthPercentage
            self.itemSpacing = itemSpacing
            self.additionalInsets = additionalInsets
        }
        
        public var sideItemTransform = Transform(alpha: 1, sizeRatio: 0.88)
        public var centerItemWidthPercentage: CGFloat = 0.63
        public var itemSpacing: CGFloat = 10
        public var additionalInsets: UIEdgeInsets = .zero
    }
    
    public struct VisibleItem {
        public let index: Int
        public weak var view: UIView!
    }
    
    public var appearance = Appearance() {
        didSet {
            guard oldValue != appearance else { return }
            reloadData()
        }
    }
    
    public weak var dataSource: CarouselViewDataSource? {
        didSet {
            guard oldValue !== dataSource else { return }
            reloadData()
        }
    }
    
    public weak var delegate: CarouselViewDelegate?
    
    public var preloadDistance: CGFloat = 80
    
    public var adjustedContentInset: UIEdgeInsets {
        let centerCellWidth = (scrollView.visibleSize.width * appearance.centerItemWidthPercentage)
        let sideInset = ((scrollView.visibleSize.width - centerCellWidth) / 2).rounded()
        
        return UIEdgeInsets(top: appearance.additionalInsets.top,
                            left: sideInset + appearance.additionalInsets.left,
                            bottom: appearance.additionalInsets.bottom,
                            right: sideInset + appearance.additionalInsets.right)
    }
    
    /// Returns the item which is closest to the center
    public var centerItemIndex: Int? {
        return snappedItemIndex(forCenterOffset: scrollView.contentOffset.x + scrollView.bounds.width / 2)
    }
    
    public var snapBehavior: SnapBehavior = .default
    
    public var visibleItems: [VisibleItem] = []
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        reloadData()
    }
    
    public func reloadData() {
        // if snap behavior was on, store currently centered item to restore it after data reload
        let centerItemIndex: Int? = (snapBehavior != .none) ? self.centerItemIndex : nil
        
        contentView.subviews.forEach { removeView($0) }

        calculateItemFrames()
        contentWidthConstraint.constant = getApproximateContentRect().width
        
        let items = addItems()
        self.visibleItems = items
        
        layoutIfNeeded()
        updateTransforms()
        
        if let centerItemIndex = centerItemIndex {
            scrollToItem(at: centerItemIndex, animated: false)
        }
    }
    
    public func scrollToItem(at index: Int, animated: Bool = true) {
        guard itemFrames.indices.contains(index) else { return }
        
        let offset = itemFrames[index].midX - (scrollView.bounds.width / 2)
        scrollView.setContentOffset(CGPoint(x: offset,
                                            y: 0), animated: animated)
    }
    
    // MARK: - Private
    
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private var contentWidthConstraint: NSLayoutConstraint!
    private var itemFrames: [CGRect] = []
    
    private func commonInit() {
        scrollView.backgroundColor = .clear
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(scrollView)
        scrollView.constraintToEdges(of: self)

        contentView.backgroundColor = .clear
        scrollView.addSubview(contentView)
        contentView.constraintToEdges(of: scrollView)
        contentView.heightAnchor.constraint(equalTo: heightAnchor).isActive = true
        
        let contentWidthConstraint = contentView.widthAnchor.constraint(equalToConstant: 0)
        self.contentWidthConstraint = contentWidthConstraint
        contentWidthConstraint.isActive = true
    }
    
    private func calculateItemFrames() {
        itemFrames = dataSource.flatMap { calculateItemFrames(from: $0) } ?? []
    }
    
    private func calculateItemFrames(from dataSource: CarouselViewDataSource) -> [CGRect] {
        layoutIfNeeded()
        
        let count = dataSource.numberOfItems(in: self)
        
        // Treat all items as "small" ones by default
        // actaully in this approach we only "enlarge" center item instead of transforming the other ones
        let spacing = (appearance.itemSpacing / appearance.sideItemTransform.sizeRatio).rounded()
        let itemWidth = (scrollView.visibleSize.width * appearance.centerItemWidthPercentage * appearance.sideItemTransform.sizeRatio).rounded()
        
        var insets = adjustedContentInset
        insets.left = ((insets.left + appearance.itemSpacing) / appearance.sideItemTransform.sizeRatio).rounded()
        insets.top = (insets.top / appearance.sideItemTransform.sizeRatio).rounded()
        insets.bottom = (insets.bottom / appearance.sideItemTransform.sizeRatio).rounded()
        
        let itemFrames = (0..<count).map { itemIndex in
            CGRect(x: (itemWidth + spacing) * CGFloat(itemIndex) + insets.left,
                   y: 0,
                   width: itemWidth,
                   height: scrollView.visibleSize.height - insets.top - insets.bottom)
        }
        
        return itemFrames
    }
    
    private func getApproximateContentRect(from frames: [CGRect]? = nil) -> CGRect {
        let frames = frames ?? itemFrames
        var contentBounds = frames.reduce(CGRect.zero) { result, rect in result.union(rect) }
        
        contentBounds.size.width += adjustedContentInset.left + adjustedContentInset.right
        contentBounds.size.height += adjustedContentInset.top + adjustedContentInset.bottom
        
        return contentBounds
    }
    
    private func snappedItemIndex(forCenterOffset centerX: CGFloat) -> Int? {
        let distanceFromItems = itemFrames.map { abs($0.midX - centerX) }
        return distanceFromItems
            .enumerated()
            .min { $0.element < $1.element }?
            .offset
    }
    
    private func snappedContentOffset(forCenterOffset centerX: CGFloat) -> CGFloat {
        let targetCenterX: CGFloat
        
        if let closestIndex = snappedItemIndex(forCenterOffset: centerX) {
            targetCenterX = itemFrames[closestIndex].midX
        } else {
            targetCenterX = centerX
        }
        
        return targetCenterX - (scrollView.bounds.width / 2)
    }
    
    private func getVisibleItemIndices(from frames: [CGRect]? = nil) -> [Int] {
        let frames = frames ?? itemFrames
        let visibleRect = CGRect(origin: scrollView.contentOffset, size: scrollView.visibleSize)
            .insetBy(dx: -preloadDistance, dy: 0)
        
        let visibleItemIndices = frames.enumerated()
            .filter { $0.element.intersects(visibleRect) }
            .map(\.offset)
        
        return visibleItemIndices
    }
    
    private func addItems(at indices: [Int]? = nil) -> [VisibleItem] {
        guard let dataSource = dataSource else { return [] }
        
        let indices = indices ?? getVisibleItemIndices()
        var result: [VisibleItem] = []
        
        let items = indices.map { (index: $0, view: dataSource.carouselView(self, cellForItemAt: $0)) }
        
        for (index, view) in items {
            let frame = itemFrames[index]
            
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(itemTapped))
            recognizer.name = "carouselView#tapRecognizer#\(index)"
            recognizer.delegate = self
            view.addGestureRecognizer(recognizer)
            
            contentView.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
            let left = view.leftAnchor.constraint(equalTo: contentView.leftAnchor, constant: frame.minX)
            left.identifier = "carouselView#leftConstraint"
            let top = view.topAnchor.constraint(equalTo: contentView.topAnchor, constant: frame.minY)
            top.identifier = "carouselView#topConstraint"
            let width = view.widthAnchor.constraint(equalToConstant: frame.width)
            width.identifier = "carouselView#widthConstraint"
            let height = view.heightAnchor.constraint(equalToConstant: frame.height)
            height.identifier = "carouselView#heightConstraint"
            
            NSLayoutConstraint.activate([left, top, width, height])
            
            result.append(VisibleItem(index: index, view: view))
        }
        
        contentView.layoutIfNeeded()
        
        return result
    }
    
    private func removeView(_ view: UIView) {
        view.removeFromSuperview()
        
        if let tapRecognizer = view.gestureRecognizers?
            .first(where: { $0.name?.hasPrefix("carouselTapRecognizer") == true }) {
            view.removeGestureRecognizer(tapRecognizer)
        }
        
        view.constraints
            .filter { $0.identifier?.hasPrefix("carouselView") == true }
            .forEach { $0.isActive = false }
    }
    
    @objc private func itemTapped(_ recognizer: UITapGestureRecognizer) {
        guard let itemIndex = recognizer.name?.components(separatedBy: "#").last.flatMap(Int.init) else { return }
        delegate?.carouselView(self, didSelectItemAt: itemIndex)
    }
    
    private func updateVisibleItems() {
        let visibleItemIndices = getVisibleItemIndices()
        guard Set(visibleItemIndices) != Set(self.visibleItems.map(\.index)) else { return }
        
        let itemsToRemove = self.visibleItems.filter { !visibleItemIndices.contains($0.index) }
        let indicesToRemove = itemsToRemove.map(\.index)
        let indicesToAdd = visibleItemIndices.filter { idx in !self.visibleItems.contains { $0.index == idx } }
        
        itemsToRemove.compactMap(\.view).forEach { removeView($0) }
        let remainingItems = self.visibleItems.filter { !indicesToRemove.contains($0.index) }
        let addedItems = addItems(at: indicesToAdd)
        
        self.visibleItems = (remainingItems + addedItems).sorted { $0.index < $1.index }
    }
    
    private func updateTransforms() {
        guard let itemSize = itemFrames.first?.size else { return }
        
        let centerOffset = scrollView.contentOffset.x + (scrollView.visibleSize.width / 2)
        
        let offscreenDistance = (scrollView.bounds.width / 2) + (itemSize.width / 2)
        let sideItemDistance = (scrollView.bounds.width * appearance.centerItemWidthPercentage / 2) + appearance.itemSpacing + itemSize.width / 2
        let sideToOffscreenRatio = sideItemDistance / offscreenDistance
        
        let sideItemTransform = TransformValues(appearance.sideItemTransform)
        let centerTransform = TransformValues(alpha: 1,
                                              xScale: 1/sideItemTransform.xScale,
                                              yScale: 1/sideItemTransform.yScale)
        
        let edgeTransform = TransformValues(alpha: sideItemTransform.alpha * sideToOffscreenRatio,
                                            xScale: sideItemTransform.xScale * sideToOffscreenRatio,
                                            yScale: sideItemTransform.yScale * sideToOffscreenRatio)
        
        // bring centermost items to front
        visibleItems
            .compactMap(\.view)
            .sorted { abs(centerOffset -  $0.frame.midX) > abs(centerOffset -  $1.frame.midX) }
            .forEach { contentView.bringSubviewToFront($0) }
        
        visibleItems.enumerated().forEach { (index, item) in
            guard let view = item.view else { return }
            
            let distanceFromCenter = centerOffset - view.frame.midX
            let distanceRatio = abs(distanceFromCenter) / offscreenDistance
            
            let transform = TransformValues.get(from: centerTransform,
                                                to: edgeTransform,
                                                progress: distanceRatio)
            
            view.alpha = transform.alpha
            view.transform = CGAffineTransform(scaleX: transform.xScale,
                                               y: transform.yScale)
        }
    }
}

extension CarouselView: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateVisibleItems()
        updateTransforms()
        
        delegate?.carouselView(self, didScrollToOffset: scrollView.contentOffset.x)
    }
    
    public func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        func index(offsetBy value: Int) -> Int? {
            let velocityCompensation = -velocity.x * 50
            let offset = scrollView.contentOffset.x + (scrollView.bounds.width / 2) + velocityCompensation
            
            guard let centerIndex = snappedItemIndex(forCenterOffset: offset),
                  case let targetIndex = centerIndex + value,
                  itemFrames.indices.contains(targetIndex) else { return nil }
            
            return targetIndex
        }
        
        let itemCenters = itemFrames.map(\.midX)
        let referenceOffset: CGFloat
        switch snapBehavior {
        case .soft:
            referenceOffset = targetContentOffset.pointee.x + scrollView.bounds.width / 2
        case .hard:
            let sign: FloatingPointSign? = (velocity.x != 0 ? velocity.x.sign : nil)
            let targetIndex: Int?
            
            switch sign {
            case .minus: targetIndex = index(offsetBy: -1)
            case .plus: targetIndex = index(offsetBy: 1)
            case .none: targetIndex = nil
            }
            
            if let targetIndex = targetIndex {
                referenceOffset = itemCenters[targetIndex]
            } else {
                referenceOffset = scrollView.contentOffset.x + scrollView.bounds.width / 2
            }
        case .none:
            return
        }
        
        let snappedOffset = snappedContentOffset(forCenterOffset: referenceOffset)
        targetContentOffset.pointee = CGPoint(x: snappedOffset, y: 0)
        
        if let snappedItemIndex = snappedItemIndex(forCenterOffset: referenceOffset) {
            delegate?.carouselView(self, willSnapToItemAt: snappedItemIndex)
        }
    }
}

private extension UIView {
    @discardableResult
    func constraintToEdges(of view: UIView) -> EdgeConstraints {
        translatesAutoresizingMaskIntoConstraints = false
        
        let left = leftAnchor.constraint(equalTo: view.leftAnchor)
        let right = rightAnchor.constraint(equalTo: view.rightAnchor)
        let top = topAnchor.constraint(equalTo: view.topAnchor)
        let bottom = bottomAnchor.constraint(equalTo: view.bottomAnchor)
        
        NSLayoutConstraint.activate([left, right, top, bottom])
        
        return EdgeConstraints(left: left, right: right, top: top, bottom: bottom)
    }
}

private struct EdgeConstraints {
    let left: NSLayoutConstraint
    let right: NSLayoutConstraint
    let top: NSLayoutConstraint
    let bottom: NSLayoutConstraint
}

private struct TransformValues {
    internal init(alpha: CGFloat, xScale: CGFloat, yScale: CGFloat) {
        self.alpha = alpha
        self.xScale = xScale
        self.yScale = yScale
    }
    
    init(_ transform: CarouselView.Transform) {
        self.alpha = transform.alpha
        self.xScale = transform.sizeRatio
        self.yScale = 1
    }
    
    let alpha: CGFloat
    let xScale: CGFloat
    let yScale: CGFloat
    
    static func get(from start: TransformValues,
                    to end: TransformValues,
                    progress: CGFloat) -> TransformValues {
        func value<T: FloatingPoint>(_ keyPath: KeyPath<Self, T>, atProgress progress: T) -> T {
            let diff = end[keyPath: keyPath] - start[keyPath: keyPath]
            return start[keyPath: keyPath] + (diff * progress)
            
        }
        
        return TransformValues(alpha: value(\.alpha, atProgress: progress),
                               xScale: value(\.xScale, atProgress: progress),
                               yScale: value(\.yScale, atProgress: progress))
    }
}

extension CarouselView: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
