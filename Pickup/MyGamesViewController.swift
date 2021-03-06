//
//  MyGamesViewController.swift
//  Pickup
//
//  Created by Nathan Dudley on 3/2/16.
//  Copyright © 2016 Pickup. All rights reserved.
//

import UIKit
import CoreLocation
import Firebase
import Parse

class MyGamesViewController: UIViewController, UITableViewDelegate, CLLocationManagerDelegate, MyGamesTableViewDelegate, DismissalDelegate {

    let METERS_IN_MILE = 1609.34
    let METERS_IN_KILOMETER = 1000.0
    let SEGUE_SHOW_GAME_DETAILS = "showGameDetailsViewController"
    let SEGUE_SHOW_NEW_GAME = "showNewGameTableViewController"
    
    
    var newGame: Game!
    var sectionTitles:[String] = []
    var gameTypes:[GameType] = []
    var games:[Game] = []
    var sortedGames:[[Game]] = [[]]
    
    let locationManager = CLLocationManager()
    var currentLocation:CLLocation? {
        didSet {
            self.tableGameList.reloadData()
        }
    }
    
    @IBOutlet weak var btnSettings: UIBarButtonItem!
    @IBOutlet weak var btnAddGame: UIBarButtonItem!
    @IBOutlet weak var tableGameList: UITableView!
    @IBOutlet weak var blurNoGames: UIVisualEffectView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.btnAddGame.tintColor = Theme.ACCENT_COLOR
        self.btnSettings.tintColor = Theme.PRIMARY_LIGHT_COLOR
        
        let gameTypePullTimeStamp: Date = getLastGameTypePull()
        
        if gameTypePullTimeStamp.compare(Date().addingTimeInterval(-24*60*60)) == ComparisonResult.orderedAscending {
            loadGameTypesFromParse()
        } else {
            loadGameTypesFromUserDefaults()
        }
        
        self.setUsersCurrentLocation()
        tableGameList.tableFooterView = UIView(frame: CGRect.zero)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        blurNoGames.isHidden = true
        loadGamesFromParse()
        self.tableGameList.reloadData()
    }
    
    //MARK: - Table View Delegate
    
    func numberOfSectionsInTableView(_ tableView: UITableView) -> Int {
        return sectionTitles.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sortedGames[section].count
    }
    
    private func tableView(_ tableView : UITableView,  titleForHeaderInSection section: Int)->String {
        return sectionTitles[section]
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return Theme.GAME_LIST_ROW_HEIGHT
    }
    
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int)
    {
        let header = view as! UITableViewHeaderFooterView
        header.textLabel?.textColor = Theme.PRIMARY_DARK_COLOR
        header.textLabel?.textAlignment = .center
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        performSegue(withIdentifier: SEGUE_SHOW_GAME_DETAILS, sender: self)
    }
    
    
    //MARK: - Table View Data Source
    
    private func tableView(_ tableView: UITableView, cellForRowAtIndexPath indexPath: IndexPath) -> MyGamesTableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as? MyGamesTableViewCell
        
        if !sortedGames.isEmpty {
            
            let game = sortedGames[(indexPath as NSIndexPath).section][(indexPath as NSIndexPath).row]
            
            cell?.lblLocationName.text = game.locationName
            cell?.lblGameDate.text = relevantDateInfo(game.eventDate as Date)
            cell?.lblDistance.text = ""
            cell?.imgGameType.image = UIImage(named: game.gameType.imageName)
            
            let latitude:CLLocationDegrees = game.latitude
            let longitude:CLLocationDegrees = game.longitude
            let gameLocation:CLLocation = CLLocation(latitude: latitude, longitude: longitude)
            if self.currentLocation != nil && Settings.sharedSettings.defaultLocation == "none" {
            let distance: Double = getDistanceBetweenLocations(gameLocation, location2: self.currentLocation!)
                    var suffix = "mi"
                if Settings.sharedSettings.distanceUnit == "kilometers" {
                    suffix = "km"
                }
                cell?.lblDistance.text = "\(distance) \(suffix)"
            }
        }
    
        return cell!
        
    }
    
    //MARK: - My Games Table View Delegate
    
    func removeGame(_ game: Game) {
        
        for index in 0 ... games.count - 1 {
            if game.id == games[index].id {
                games.remove(at: index)
                break
            }
        }
        
        self.sortedGames = self.sortGamesByOwner(games)
        self.tableGameList.reloadData()
    }
    
    //MARK: - User Defaults
    
    fileprivate func getLastGameTypePull() -> Date {
        
        var lastPull: Date
        
        if let lastGameTypePull = UserDefaults.standard.object(forKey: "gameTypePullTimeStamp") as? Date {
            lastPull = lastGameTypePull
        } else {
            lastPull = Date().addingTimeInterval(-25 * 60 * 60)
            UserDefaults.standard.set(lastPull, forKey: "gameTypePullTimeStamp")
        }
        
        return lastPull
    }
    
    
    fileprivate func loadGameTypesFromUserDefaults() {
        
        var gameTypeArray: NSMutableArray = []
        
        if let gameTypeArrayFromDefaults = UserDefaults.standard.object(forKey: "gameTypes") as? NSArray {
            gameTypeArray = gameTypeArrayFromDefaults.mutableCopy() as! NSMutableArray
            
            for gameType in gameTypeArray {
                self.gameTypes.append(GameType.deserializeGameType(gameType as! [String : String]))
            }
        }
        
    }
    
    fileprivate func saveGameTypesToUserDefaults() {
        
        let gameTypeArray: NSMutableArray = []
        
        for gameType in self.gameTypes {
            let serializedGameType = GameType.serializeGameType(gameType)
            gameTypeArray.add(serializedGameType)
        }
        
        UserDefaults.standard.set(gameTypeArray, forKey: "gameTypes")
        UserDefaults.standard.set(Date(), forKey: "gameTypePullTimeStamp")
    }
    
    
    //MARK: - Parse
    
    fileprivate func loadGamesFromParse() {
        let gameQuery = PFQuery(className: "Game")
        
        gameQuery.whereKey("date", greaterThanOrEqualTo: Date().addingTimeInterval(-1.5 * 60 * 60))
        gameQuery.whereKey("date", lessThanOrEqualTo: Date().addingTimeInterval(2 * 7 * 24 * 60 * 60))
        gameQuery.whereKey("objectId", containedIn: getJoinedGamesFromUserDefaults())
        gameQuery.whereKey("isCancelled", equalTo: false)
        
        gameQuery.findObjectsInBackground { (objects, error) -> Void in
            if let gameObjects = objects {
                self.games.removeAll(keepingCapacity: true)
                
                var gameObjectCount = 0
                
                for gameObject in gameObjects {
                    
                    let gameId = (gameObject["gameType"] as AnyObject).objectId as String!

                    let game = GameConverter.convertParseObject(gameObject, selectedGameType: self.getGameTypeById(gameId!))
                    
                    if (gameObject["owner"] as AnyObject).objectId == PFUser.current()?.objectId {
                        game.userIsOwner = true
                    }
                    
                    game.userJoined = true
                    self.games.append(game)
                    gameObjectCount += 1
                }
                
                if gameObjectCount == 0 {
                    self.blurNoGames.isHidden = false
                }
                
            } else {
                print(error ?? "Unable to load games from parse")
            }
            
            DispatchQueue.main.async {
                self.sortedGames = self.sortGamesByOwner(self.games)
                self.tableGameList.reloadData()
            }
        }
    }
    
    fileprivate func loadGameTypesFromParse() {
        
        let gameTypeQuery = PFQuery(className: "GameType")
        gameTypeQuery.findObjectsInBackground { (objects, error) -> Void in
            if let gameTypeObjects = objects {
                
                self.gameTypes.removeAll(keepingCapacity: true)
                
                for gameTypeObject in gameTypeObjects {
                    let gameType = GameTypeConverter.convertParseObject(gameTypeObject)
                    DispatchQueue.main.async {
                        self.gameTypes.append(gameType)
                    }
                }
            }
            
            self.saveGameTypesToUserDefaults()
        }
    }
    
    //MARK: - Sorting functions
    
    fileprivate func getGameTypeById (_ gameId: String) -> GameType {
        
        var returnedGameType = self.gameTypes[0]
        
        for gameType in self.gameTypes {
            if gameId == gameType.id {
                returnedGameType = gameType
                break
            }
        }
        
        return returnedGameType
    }
    
    fileprivate func sortGamesByOwner(_ games: [Game]) -> [[Game]] {
        
        var createdGames:[Game] = []
        var joinedGames:[Game] = []
        var combinedGamesArray:[[Game]] = [[]]
        
        //TODO: This won't work on a new year
        let sortedGameArray = games.sorted { (gameOne, gameTwo) -> Bool in
            let firstElementDay = (Calendar.current as NSCalendar).ordinality(of: .day, in: .year, for: gameOne.eventDate as Date)
            let secondElementDay = (Calendar.current as NSCalendar).ordinality(of: .day, in: .year, for: gameTwo.eventDate as Date)
            
            return firstElementDay < secondElementDay
        }
        
        
        for game in sortedGameArray {
            if game.userIsOwner {
                createdGames.append(game)
            } else {
                joinedGames.append(game)
            }
        }
        
        self.sectionTitles.removeAll()
        combinedGamesArray.removeAll()
        
        if !createdGames.isEmpty {
            combinedGamesArray.append(createdGames)
            self.sectionTitles.append("Created Games")
        }
        
        if !joinedGames.isEmpty {
            combinedGamesArray.append(joinedGames)
            self.sectionTitles.append("Joined Games")
        }
        
        return combinedGamesArray
    }
    
    
    
    //MARK: - Location Manager Delegate
    //TODO: Abstract location methods into their own class
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        let location:CLLocationCoordinate2D = manager.location!.coordinate
        currentLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        
        if currentLocation != nil {
            locationManager.stopUpdatingLocation()
        }
        
        tableGameList.reloadData()
    }
    
    func setUsersCurrentLocation() {
        self.locationManager.requestWhenInUseAuthorization()
        
        if CLLocationManager.locationServicesEnabled() {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.startUpdatingLocation()
        }
    }
    
    func getDistanceBetweenLocations(_ location1: CLLocation, location2: CLLocation) -> Double {
        
        var distanceUnitMeasurement: Double
        
        if Settings.sharedSettings.distanceUnit == "miles" {
            distanceUnitMeasurement = METERS_IN_MILE
        } else {
            distanceUnitMeasurement = METERS_IN_KILOMETER
        }
        
        let distance:Double = roundToDecimalPlaces(location1.distance(from: location2) / distanceUnitMeasurement, places: 1)
        return distance
    }
    
    func roundToDecimalPlaces(_ number: Double, places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return round(number * divisor) / divisor
    }
    
    //MARK: - Dismissal Delegate
    func finishedShowing(_ viewController: UIViewController) {
        
        self.dismiss(animated: true, completion: nil)
        performSegue(withIdentifier: SEGUE_SHOW_GAME_DETAILS, sender: self)
        
        return
    }
    
    func setNewGame(_ game: Game) {
        self.newGame = game
    }
    
    
    func dateCompare(_ eventDate: Date) -> String {
        
        let dateToday: Date = Date().addingTimeInterval(-1.5 * 60 * 60)
        
        let dateComparisonResult:ComparisonResult = dateToday.compare(eventDate)
        var resultString:String = ""
        
        if dateComparisonResult == ComparisonResult.orderedAscending || dateComparisonResult == ComparisonResult.orderedSame
        {
            let todayWeekday = (Calendar.current as NSCalendar).components([.weekday], from: Date()).weekday
            let eventWeekday = (Calendar.current as NSCalendar).components([.weekday], from: eventDate).weekday
            
            let today = (Calendar.current as NSCalendar).ordinality(of: .day, in: .year, for: Date())
            let eventDay = (Calendar.current as NSCalendar).ordinality(of: .day, in: .year, for: eventDate)
            
            if todayWeekday == eventWeekday && today == eventDay {
                resultString = "TODAY"
            } else if todayWeekday! + 1 == eventWeekday! && today + 1 == eventDay  {
                resultString = "TOMORROW"
            } else if eventWeekday! > todayWeekday! && today + 7 >= eventDay {
                resultString = "THIS WEEK"
            } else {
                resultString = "NEXT WEEK"
            }
        }
        
        return resultString
    }
    
    
    //MARK: - Date Formatting
    
    func relevantDateInfo(_ eventDate: Date) -> String {
        
        var relevantDateString = ""
        
        switch(dateCompare(eventDate)) {
        case "TODAY":
            relevantDateString = "Today  \(DateUtilities.dateString(eventDate, dateFormatString: DateFormatter.TWELVE_HOUR_TIME.rawValue))"
            break
        case "TOMORROW":
            relevantDateString = "Tomorrow  \(DateUtilities.dateString(eventDate, dateFormatString: DateFormatter.TWELVE_HOUR_TIME.rawValue))"
            break
        case "THIS WEEK":
            relevantDateString = DateUtilities.dateString(eventDate, dateFormatString: "\(DateFormatter.WEEKDAY.rawValue)  \(DateFormatter.TWELVE_HOUR_TIME.rawValue)")
            break
        case "NEXT WEEK":
            relevantDateString = DateUtilities.dateString(eventDate, dateFormatString: "\(DateFormatter.WEEKDAY.rawValue)  \(DateFormatter.TWELVE_HOUR_TIME.rawValue)")
            break
        default:
            break
        }
        
        return relevantDateString
    }
    
    
    //MARK: - User Defaults
    
    fileprivate func getJoinedGamesFromUserDefaults() -> [String] {
        
        var joinedGamesIds: [String] = []
        
        if let joinedGames = UserDefaults.standard.object(forKey: "userJoinedGamesById") as? NSArray {
            let gameIdArray = joinedGames.mutableCopy()
            joinedGamesIds = gameIdArray as! [String]
            
        } else {
            //TODO: Display that there are no joined games
        }
        
        return joinedGamesIds
    }
    

    
     //MARK: - Navigation

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == SEGUE_SHOW_GAME_DETAILS {
            
            let gameDetailsViewController = segue.destination as! GameDetailsViewController
            var game: Game
            
            if let indexPath = tableGameList.indexPathForSelectedRow {
                game = sortedGames[(indexPath as NSIndexPath).section][(indexPath as NSIndexPath).row]
            } else {
                game = self.newGame!
            }
            
            gameDetailsViewController.game = game
            gameDetailsViewController.gameTypes = self.gameTypes
            
            if game.userIsOwner == true {
                gameDetailsViewController.userStatus = .user_OWNED
            } else if game.userJoined == true {
                gameDetailsViewController.userStatus = .user_JOINED
            } else {
                gameDetailsViewController.userStatus = .user_NOT_JOINED
            }
            
            gameDetailsViewController.navigationItem.leftItemsSupplementBackButton = true
        } else if segue.identifier == SEGUE_SHOW_NEW_GAME {
            
            let navigationController = segue.destination as! UINavigationController
            let newGameTableViewController = navigationController.viewControllers.first as! NewGameTableViewController
            newGameTableViewController.dismissalDelegate = self
            newGameTableViewController.gameTypes = self.gameTypes
            
        }

    }
    

}
