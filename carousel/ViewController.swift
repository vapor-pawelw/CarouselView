//
//  ViewController.swift
//  carousel
//
//  Created by Paweł Wojtkowiak on 04/03/2021.
//

import UIKit

private let bgColors: [UIColor] = [.red, .green, .blue, .yellow, .black, .brown, .cyan, .gray]

class ViewController: UIViewController {
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
        
        carouselView.isInfinite = false
        carouselView.snapBehavior = .soft
        carouselView.updateAppearance { appearance in
            appearance.sideItemTransform.alpha = 0.8
            appearance.centerItemWidth = .heightRatio(0.4)
        }
        carouselView.scrollToItem(at: 4, animated: false)
    }
}

extension ViewController: CarouselViewDataSource {
    func numberOfItems(in carouselView: CarouselView) -> Int {
        return 10
    }
    
    func carouselView(_ carouselView: CarouselView, cellForItemAt index: Int) -> UIView {
        let view = UIView()
        view.backgroundColor = bgColors[index % bgColors.count]
        
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
}

extension ViewController: CarouselViewDelegate {
    func carouselView(_ carouselView: CarouselView, didScrollToOffset offset: CGFloat) {
        carouselView.visibleItems.forEach { item in
            guard let label = item.view.subviews.first as? UILabel else { return }
            
            let wScale = item.view.frame.width / carouselView.centerItemSize.width
            let hScale = item.view.frame.height / carouselView.centerItemSize.height
            
            label.text = """
                \(item.index)
                W: \(formatter.string(from: wScale as NSNumber)!)
                H: \(formatter.string(from: hScale as NSNumber)!)
                Ratio: \(formatter.string(from: (wScale/hScale) as NSNumber)!)
                """
        }
    }
}
