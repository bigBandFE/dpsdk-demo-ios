import UIKit
import DPSDKKit

class MiniappTableViewController: UITableViewController {

    struct MiniappData {
        let appId: String
        let name: String
    }

    private let miniapps: [MiniappData] = [
        MiniappData(appId: "lounge", name: "Lounge"),
        MiniappData(appId: "fastTrack", name: "Fast Track")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = "DPApps"
        navigationController?.navigationBar.prefersLargeTitles = true

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "MiniappCell")
        tableView.separatorStyle = .singleLine
    }

    // MARK: - Table view data source

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return miniapps.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "MiniappCell", for: indexPath)
        cell.textLabel?.text = miniapps[indexPath.row].name
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let app = miniapps[indexPath.row]
        DPSDK.open(appId: app.appId, from: self)
    }
}
