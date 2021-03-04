//
//  ViewController.swift
//  carousel
//
//  Created by Paweł Wojtkowiak on 04/03/2021.
//

import UIKit

private let bgColors: [UIColor] = [.red, .green, .blue, .yellow, .black, .brown, .cyan, .gray]

class ViewController: UIViewController {
    var views: [UIView] = {
        let soManyColors = (1...2).flatMap { _ in bgColors }
        return soManyColors.enumerated().map { (index, color) in
            let view = UIView()
            view.backgroundColor = color
            
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
            
            label.numberOfLines = 0
            label.font = .boldSystemFont(ofSize: 24)
            label.text = "\(index)"
            label.textColor = .white
            label.textAlignment = .center
            
            return view
        }
    }()
    
    lazy var formatter: NumberFormatter = {
        let nf = NumberFormatter()
        nf.maximumFractionDigits = 3
        return nf
    }()

    @IBOutlet weak var carouselView: CarouselView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        carouselView.dataSource = self
        carouselView.delegate = self
        
        carouselView.appearance.centerItemWidthPercentage = 0.3
        carouselView.appearance.itemSpacing = 0
    }
}

extension ViewController: CarouselViewDataSource {
    func numberOfItems(in carouselView: CarouselView) -> Int {
        return views.count
    }
    
    func carouselView(_ carouselView: CarouselView, cellForItemAt index: Int) -> UIView {
        return views[index]
    }
}

extension ViewController: CarouselViewDelegate {
    func carouselView(_ carouselView: CarouselView, didScrollToOffset offset: CGFloat) {
        carouselView.visibleItems.forEach { item in
            guard let label = item.view.subviews.first as? UILabel else { return }
            
            let defaultWidth = carouselView.bounds.width * carouselView.appearance.centerItemWidthPercentage * carouselView.appearance.sideItemTransform.sizeRatio
            
            let wScale = item.view.frame.width / defaultWidth
            let hScale = item.view.frame.height / carouselView.bounds.height
            
            label.text = """
                \(item.index)
                W: \(formatter.string(from: wScale as NSNumber)!)
                H: \(formatter.string(from: hScale as NSNumber)!)
                """
        }
    }
}
