//
//  CarouselView.swift
//  dietbyann
//
//  Created by Paweł Wojtkowiak on 04/03/2021.
//  Copyright © 2021 VAPOR Paweł Wojtkowiak. All rights reserved.
//

// TODO:
// - smooth infinite scrolling for .soft and .none snap behaviors
// - for non-infinite, scrollview bounce works bad for last cell

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
        
        public var alpha: CGFloat
        public var sizeRatio: CGFloat
    }
    
    public enum CenterItemWidth: Equatable {
        case contentWidthRatio(CGFloat)
        case heightRatio(CGFloat)
    }
    
    public struct Appearance: Equatable {
        public init(sideItemTransform: CarouselView.Transform = Transform(alpha: 1, sizeRatio: 0.88), centerItemWidth: CenterItemWidth = .contentWidthRatio(0.63), itemSpacing: CGFloat = 10, additionalInsets: UIEdgeInsets = .zero) {
            self.sideItemTransform = sideItemTransform
            self.centerItemWidth = centerItemWidth
            self.itemSpacing = itemSpacing
            self.additionalInsets = additionalInsets
        }
        
        public var sideItemTransform = Transform(alpha: 1, sizeRatio: 0.88)
        public var centerItemWidth: CenterItemWidth = .contentWidthRatio(0.63)
        public var itemSpacing: CGFloat = 10
        public var additionalInsets: UIEdgeInsets = .zero
    }
    
    public struct VisibleItem {
        public let index: Int
        public let actualIndex: Int
        public weak var view: UIView!
    }
    
    public var appearance = Appearance() {
        didSet {
            guard oldValue != appearance, reloadDataOnAppearanceUpdate else { return }
            reloadData()
        }
    }
    
    public weak var dataSource: CarouselViewDataSource? {
        didSet {
            guard oldValue !== dataSource else { return }
            reloadData()
        }
    }
    
    public var isInfinite: Bool = true {
        didSet {
            guard oldValue != isInfinite else { return }
            reloadData()
        }
    }
    
    public weak var delegate: CarouselViewDelegate?
    
    public var preloadDistance: CGFloat = 80
    
    public var adjustedContentInset: UIEdgeInsets {
        let sideInset = ((scrollView.visibleSize.width - centerItemSize.width) / 2).rounded()
        let actualSideInset = isInfinite ? 0 : (sideInset + appearance.additionalInsets.left)
        
        return UIEdgeInsets(top: appearance.additionalInsets.top.rounded(),
                            left: actualSideInset.rounded(),
                            bottom: appearance.additionalInsets.bottom.rounded(),
                            right: actualSideInset.rounded())
    }
    
    /// Returns the item which is closest to the center
    public var centerItemIndex: Int? {
        return actualCenterItemIndex.flatMap { $0 % (itemFrames.count / infiniteMultiplier) }
    }
    
    public var snapBehavior: SnapBehavior = .default
    
    public private(set) var visibleItems: [VisibleItem] = []
    
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
        let actualCenterItemIndex: Int? = (snapBehavior != .none) ? self.actualCenterItemIndex : nil
        
        contentView.subviews.forEach { removeView($0) }

        calculateItemFrames()
        contentWidthConstraint.constant = getContentRect().width
        
        removeAllItems()
        let items = addItems()
        self.visibleItems = items
        
        layoutIfNeeded()
        updateTransforms()
        
        updateInfiniteScrollOffset()
        
        if let actualCenterItemIndex = actualCenterItemIndex {
            scrollToIndex(actualCenterItemIndex, animated: false)
        }
    }
    
    public func scrollToItem(at index: Int, animated: Bool = true) {
        let actualCount = itemFrames.count / infiniteMultiplier
        guard actualCount > index else { return }
        
        let closestIndex = (1...infiniteMultiplier)
            .map { $0 * index }
            .min { abs($0 - index) < abs($1 - index) }!
        
        scrollToIndex(closestIndex, animated: animated)
    }
    
    public func updateAppearance(_ updateClosure: (inout Appearance) -> Void) {
        reloadDataOnAppearanceUpdate = false
        updateClosure(&appearance)
        reloadDataOnAppearanceUpdate = true
        reloadData()
    }
    
    // MARK: - Internal
    
    var centerItemSize: CGSize {
        guard scrollView.visibleSize.width > 0 else { return .zero }
        
        let height = scrollView.visibleSize.height - appearance.additionalInsets.top - appearance.additionalInsets.bottom
        
        let width: CGFloat
        switch appearance.centerItemWidth {
        case .contentWidthRatio(let ratio):
            width = (ratio * scrollView.visibleSize.width).rounded()
        case .heightRatio(let ratio):
            width = (height * ratio).rounded()
        }
        
        return CGSize(width: width, height: height)
    }
    
    func getSpacing(betweenItemsWithSizeRatios ratios: [CGFloat] = []) -> CGFloat {
        return appearance.itemSpacing - ratios.reduce(0) { result, ratio in
            return result + (centerItemSize.width * (1 - ratio)) / 2
        }.rounded()
    }
    
    var sideItemSpacing: CGFloat {
        return getSpacing(betweenItemsWithSizeRatios: [1, appearance.sideItemTransform.sizeRatio])
    }
    
    // MARK: - Private
    
    private var reloadDataOnAppearanceUpdate = true
    
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private var contentWidthConstraint: NSLayoutConstraint!
    private var itemFrames: [CGRect] = []
    
    private var infiniteMultiplier: Int { return isInfinite ? 3 : 1 }
    
    public var actualCenterItemIndex: Int? {
        return actualSnappedItemIndex(forCenterOffset: scrollView.contentOffset.x + scrollView.visibleSize.width / 2)
    }
    
    private var realItemsCount: Int {
        return itemFrames.count / infiniteMultiplier
    }
    
    private var targetAnimationOffset: CGFloat?
    
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
        layoutIfNeeded()
        itemFrames = dataSource.flatMap { calculateItemFrames(from: $0) } ?? []
    }
    
    private func calculateItemFrames(from dataSource: CarouselViewDataSource) -> [CGRect] {
        let itemsCount = dataSource.numberOfItems(in: self)
        let actualCount = itemsCount * infiniteMultiplier
        
        let itemFrames = (0..<actualCount).map { index -> CGRect in
            return CGRect(x: (centerItemSize.width + sideItemSpacing) * CGFloat(index) + adjustedContentInset.left,
                          y: 0,
                          width: centerItemSize.width,
                          height: centerItemSize.height)
        }
        
        return itemFrames
    }
    
    private func getContentRect(from frames: [CGRect]? = nil) -> CGRect {
        let frames = frames ?? itemFrames
        var contentBounds = frames.reduce(CGRect.zero) { result, rect in result.union(rect) }
        
        contentBounds.size.width += adjustedContentInset.left + adjustedContentInset.right
        contentBounds.size.height += adjustedContentInset.top + adjustedContentInset.bottom
        
        return contentBounds
    }
    
    private func actualSnappedItemIndex(forCenterOffset centerX: CGFloat) -> Int? {
        guard !itemFrames.isEmpty else { return nil }
        
        let distanceFromItems = itemFrames.map { abs($0.midX - centerX) }
        return distanceFromItems
            .enumerated()
            .min { $0.element < $1.element }!
            .offset
    }
    
    private func actualSnappedContentOffset(forCenterOffset centerX: CGFloat) -> CGFloat {
        let targetCenterX: CGFloat
        
        if let closestIndex = actualSnappedItemIndex(forCenterOffset: centerX) {
            targetCenterX = itemFrames[closestIndex].midX
        } else {
            targetCenterX = centerX
        }
        
        return targetCenterX - (scrollView.visibleSize.width / 2)
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
    
    private func removeAllItems() {
        visibleItems.map(\.view).forEach { removeView($0) }
    }
    
    private func addItems(at actualIndices: [Int]? = nil) -> [VisibleItem] {
        guard let dataSource = dataSource else { return [] }
        
        let indices = actualIndices ?? getVisibleItemIndices()
        var result: [VisibleItem] = []
        
        let items = indices.map { actualIndex -> (index: Int, view: UIView) in
            return (index: actualIndex,
                    view: dataSource.carouselView(self,
                                                  cellForItemAt: getRealIndex(forActualIndex: actualIndex)))
        }
        
        for (actualIndex, view) in items {
            let frame = itemFrames[actualIndex]
            
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(itemTapped))
            recognizer.name = "carouselView#tapRecognizer#\(actualIndex)"
            recognizer.delegate = self
            view.addGestureRecognizer(recognizer)
            view.tag = actualIndex
            
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
            
            result.append(VisibleItem(index: getRealIndex(forActualIndex: actualIndex),
                                      actualIndex: actualIndex,
                                      view: view))
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
        delegate?.carouselView(self,
                               didSelectItemAt: getRealIndex(forActualIndex: itemIndex))
    }
    
    private func updateVisibleItems() {
        let visibleItemIndices = getVisibleItemIndices()
        guard Set(visibleItemIndices) != Set(self.visibleItems.map(\.actualIndex)) else { return }
        
        let itemsToRemove = self.visibleItems.filter { !visibleItemIndices.contains($0.actualIndex) }
        let indicesToRemove = itemsToRemove.map(\.actualIndex)
        let indicesToAdd = visibleItemIndices.filter { idx in !self.visibleItems.contains { $0.actualIndex == idx } }
        
        itemsToRemove.compactMap(\.view).forEach { removeView($0) }
        let remainingItems = self.visibleItems.filter { !indicesToRemove.contains($0.actualIndex) }
        let addedItems = addItems(at: indicesToAdd)
        
        self.visibleItems = (remainingItems + addedItems).sorted { $0.index < $1.index }
    }
    
    private func updateTransforms() {
        guard !visibleItems.isEmpty else { return }
        
        let centerOffset = scrollView.contentOffset.x + (scrollView.visibleSize.width / 2)
        let sideItemDistance = (centerItemSize.width / 2) + sideItemSpacing + (centerItemSize.width * appearance.sideItemTransform.sizeRatio / 2)
        
        let centerTransform = TransformValues.identity
        let sideItemTransform = TransformValues(appearance.sideItemTransform)
        
        // bring centermost items to front
        visibleItems
            .compactMap(\.view)
            .sorted { abs(centerOffset -  $0.frame.midX) > abs(centerOffset -  $1.frame.midX) }
            .forEach { contentView.bringSubviewToFront($0) }
        
        let transforms = visibleItems.map { item -> TransformData in
            guard let view = item.view else { return .zero }
            
            let distanceFromCenter = centerOffset - view.frame.midX
            let distanceRatio = abs(distanceFromCenter) / sideItemDistance
            
            let values = TransformValues.get(from: centerTransform,
                                             to: sideItemTransform,
                                             progress: distanceRatio)
            
            return TransformData(values: values, distanceFromCenter: distanceFromCenter)
        }
        
        visibleItems.indices.forEach { index in
            let item = visibleItems[index]
            let transform = transforms[index]
            guard let view = item.view else { return }
            
            // bring further side elements closer to the center
            // due to spacing being calculated for side item only by default
            let distanceSign: CGFloat = (transform.distanceFromCenter >= 0) ? 1 : -1
            let scaleDiff = max(appearance.sideItemTransform.sizeRatio - transform.values.xScale, 0)
            let sideItemWidth = centerItemSize.width * appearance.sideItemTransform.sizeRatio
            let xTransformCompensation = scaleDiff * (sideItemWidth + appearance.itemSpacing) * distanceSign
            
            view.alpha = transform.values.alpha
            view.transform = CGAffineTransform(translationX: xTransformCompensation, y: 0)
                .scaledBy(x: transform.values.xScale, y: transform.values.yScale)
        }
    }
    
    private func scrollToIndex(_ index: Int, animated: Bool = true) {
        guard itemFrames.indices.contains(index) else { return }
        
        let offset = itemFrames[index].midX - (scrollView.visibleSize.width / 2)
        scrollView.setContentOffset(CGPoint(x: offset,
                                            y: 0), animated: animated)
    }
    
    private func updateInfiniteScrollOffset() {
        guard isInfinite else { return }
        
        let offset = getScrollOffset(for: scrollView.contentOffset.x)
        
        if offset != scrollView.contentOffset.x {
            scrollView.setContentOffset(CGPoint(x: offset, y: 0), animated: false)
        }
    }
    
    private func snapToClosestItem(animated: Bool = true) {
        guard let index = actualCenterItemIndex else { return }
        scrollToIndex(index, animated: animated)
    }
    
    private func getScrollOffset(for offset: CGFloat) -> CGFloat {
        guard isInfinite else { return offset }
        
        let midSectionIndex = (infiniteMultiplier - 1) / 2
        let sectionsRange = 0...(infiniteMultiplier - 1)
        
        let sectionSize = scrollView.contentSize.width / CGFloat(infiniteMultiplier)
        
        let offsetRanges = sectionsRange
            .map { sectionIndex in
                (CGFloat(sectionIndex) * sectionSize)...(CGFloat(sectionIndex + 1) * sectionSize)
            }
        
        let midRange = offsetRanges[midSectionIndex]
        
        var offset = offset
        while !midRange.contains(offset) {
            if offset < midRange.lowerBound { offset += sectionSize }
            if offset > midRange.upperBound { offset -= sectionSize }
        }
        
        return offset
    }
    
    private func getRealIndex(forActualIndex index: Int) -> Int {
        return index % realItemsCount
    }
}

extension CarouselView: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateVisibleItems()
        updateTransforms()
        
        delegate?.carouselView(self, didScrollToOffset: scrollView.contentOffset.x)
        
        if scrollView.isCloseToContentEdge {
            let targetOffset = targetAnimationOffset
            let oldOffset = scrollView.contentOffset.x
            updateInfiniteScrollOffset()
            
            if let targetOffset = targetOffset {
                let offsetDiff = targetOffset - oldOffset
                let offset = scrollView.contentOffset.x + offsetDiff
                scrollView.setContentOffset(CGPoint(x: offset, y: 0), animated: true)
                targetAnimationOffset = nil
            }
        }
    }
    
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        updateInfiniteScrollOffset()
    }
    
    public func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let offsetRange = (0...(scrollView.contentSize.width - scrollView.visibleSize.width))
        let targetOffset = targetContentOffset.pointee.x
        let isTargetInContent = offsetRange.contains(targetOffset)
        
        guard isInfinite || isTargetInContent else { return }
        
        func index(offsetBy value: Int) -> Int? {
            let velocityCompensation = -velocity.x * 50
            let offset = scrollView.contentOffset.x + (scrollView.visibleSize.width / 2) + velocityCompensation
            
            guard let centerIndex = actualSnappedItemIndex(forCenterOffset: offset),
                  case let targetIndex = centerIndex + value,
                  itemFrames.indices.contains(targetIndex) else { return nil }
            
            return targetIndex
        }
        
        let itemCenters = itemFrames.map(\.midX)
        let referenceOffset: CGFloat
        switch snapBehavior {
        case .soft:
            referenceOffset = targetOffset + scrollView.visibleSize.width / 2
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
                referenceOffset = scrollView.contentOffset.x + scrollView.visibleSize.width / 2
            }
        case .none:
            return
        }
        
        let actualSnappedOffset = actualSnappedContentOffset(forCenterOffset: referenceOffset)
        targetContentOffset.pointee = CGPoint(x: actualSnappedOffset, y: 0)
        targetAnimationOffset = actualSnappedOffset
        
        if let snappedItemIndex = actualSnappedItemIndex(forCenterOffset: referenceOffset) {
            let realIndex = getRealIndex(forActualIndex: snappedItemIndex)
            delegate?.carouselView(self, willSnapToItemAt: realIndex)
        }
    }
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateInfiniteScrollOffset()

        if snapBehavior != .none {
            snapToClosestItem()
        }
        
        targetAnimationOffset = nil
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

private struct TransformData {
    static let zero = TransformData(values: .identity, distanceFromCenter: 0)
    
    let values: TransformValues
    let distanceFromCenter: CGFloat
}

private struct TransformValues {
    static let identity = TransformValues(alpha: 1, xScale: 1, yScale: 1)
    
    internal init(alpha: CGFloat, xScale: CGFloat, yScale: CGFloat) {
        self.alpha = alpha
        self.xScale = xScale
        self.yScale = yScale
    }
    
    init(_ transform: CarouselView.Transform) {
        self.alpha = transform.alpha
        self.xScale = transform.sizeRatio
        self.yScale = transform.sizeRatio
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

private extension UIScrollView {
    var isCloseToContentEdge: Bool {
        let minDistanceToEdge: CGFloat = 40
        let isCloseToEdge = (contentOffset.x <= minDistanceToEdge || contentOffset.x >= (contentSize.width - bounds.size.width - minDistanceToEdge))
        
        return isCloseToEdge
    }
}

public extension CarouselView.CenterItemWidth {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.contentWidthRatio(let valA), .contentWidthRatio(let valB)): return valA == valB
        case (.heightRatio(let valA), .heightRatio(let valB)): return valA == valB
        default: return false
        }
    }
}
