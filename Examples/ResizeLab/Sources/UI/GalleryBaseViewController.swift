import UIKit

@MainActor
class GalleryBaseViewController: UIViewController, UICollectionViewDataSource {
    private(set) var scenario: ResizeScenario
    let layout = UICollectionViewFlowLayout()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let statusLabel = UILabel()
    private let colors: [UIColor] = [
        .systemTeal, .systemBlue, .systemOrange, .systemIndigo,
        .systemMint, .systemPink, .systemCyan, .systemPurple,
        .systemGreen, .systemYellow, .systemRed, .systemBrown,
    ]

    init(scenario: ResizeScenario) {
        self.scenario = scenario
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.register(DemoCell.self, forCellWithReuseIdentifier: DemoCell.reuseIdentifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.textColor = .secondaryLabel
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            collectionView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
        ])
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
    }

    func setScenario(_ scenario: ResizeScenario) {
        guard self.scenario != scenario else { return }
        self.scenario = scenario
        updateLayout()
    }

    func updateLayout() {
        preconditionFailure("Subclasses define their layout assumptions")
    }

    func apply(columns: Int, contentWidth: CGFloat, note: String) {
        let safeColumns = max(columns, 1)
        let spacing = CGFloat(safeColumns - 1) * layout.minimumInteritemSpacing
        let itemWidth = max(56, (contentWidth - spacing) / CGFloat(safeColumns))
        layout.itemSize = CGSize(width: itemWidth, height: 74)
        statusLabel.text = note
        layout.invalidateLayout()
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { colors.count }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: DemoCell.reuseIdentifier,
            for: indexPath
        ) as? DemoCell else { return UICollectionViewCell() }
        cell.configure(number: indexPath.item + 1, color: colors[indexPath.item])
        return cell
    }
}

private final class DemoCell: UICollectionViewCell {
    static let reuseIdentifier = "DemoCell"
    private let numberLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 16
        contentView.layer.cornerCurve = .continuous
        numberLabel.font = .preferredFont(forTextStyle: .headline)
        numberLabel.textColor = .white
        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(numberLabel)
        NSLayoutConstraint.activate([
            numberLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            numberLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(number: Int, color: UIColor) {
        numberLabel.text = String(format: "%02d", number)
        contentView.backgroundColor = color
        accessibilityLabel = "Gallery item \(number)"
    }
}
