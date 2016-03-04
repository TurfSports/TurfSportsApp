//
//  HomeTableViewController.swift
//  Pickup
//
//  Created by Nathan Dudley on 2/8/16.
//  Copyright © 2016 Pickup. All rights reserved.
//

import UIKit
import Parse
import CoreLocation

class HomeTableViewController: UITableViewController, CLLocationManagerDelegate {
    
    let SEGUE_SHOW_GAMES = "showGamesTableViewController"
    let SEGUE_SHOW_NEW_GAME = "showNewGameTableViewController"
    let  SEGUE_SHOW_MY_GAMES = "showMyGamesViewController"
    
    var gameTypes:[GameType] = []
    var gameCountLoaded:Bool = false {
        didSet {
            self.tableView.reloadData()
        }
    }
    let locationManager = CLLocationManager()
    var currentLocation:CLLocation? {
        didSet {
            loadGameCounts()
        }
    }
    
    @IBOutlet weak var addNewGameButton: UIBarButtonItem!
    @IBOutlet weak var settingsButton: UIBarButtonItem!
    
    override func viewDidLoad() {
        
        let gameTypePullTimeStamp: NSDate = getLastGameTypePull()
        
        if gameTypePullTimeStamp.compare(NSDate().dateByAddingTimeInterval(-24*60*60)) == NSComparisonResult.OrderedAscending {
            print("Loading Games From Parse")
            loadGameTypesFromParse()
        } else {
            print("Loading Games From User Defaults")
            loadGameTypesFromUserDefaults()
        }
        
        super.viewDidLoad()
        addNewGameButton.tintColor = Theme.ACCENT_COLOR
        settingsButton.tintColor = Theme.PRIMARY_LIGHT_COLOR
        self.navigationController!.navigationBar.tintColor = Theme.PRIMARY_LIGHT_COLOR
        
        setUsersCurrentLocation()
    }

    override func viewDidAppear(animated: Bool) {

    }
    
    private func getLastGameTypePull() -> NSDate {
        
        var lastPull: NSDate
        
        if let lastGameTypePull = NSUserDefaults.standardUserDefaults().objectForKey("gameTypePullTimeStamp") as? NSDate {
            lastPull = lastGameTypePull
        } else {
            lastPull = NSDate().dateByAddingTimeInterval(-25 * 60 * 60)
            NSUserDefaults.standardUserDefaults().setObject(lastPull, forKey: "gameTypePullTimeStamp")
        }
        
        return lastPull
    }
    
    // MARK: - Table view data source

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return gameTypes.count
    }
    
    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> HomeTableViewCell {
        let cell = tableView.dequeueReusableCellWithIdentifier("Cell", forIndexPath: indexPath) as? HomeTableViewCell

        let gameType = gameTypes[indexPath.row]
        
        cell?.lblSport.text = gameType.displayName
        cell?.imgSport.image = UIImage(named: gameType.imageName)
//        cell?.lblAvailableGames.text = "Testing"
        
        if self.gameCountLoaded {
            if gameType.gameCount > 0 {
                cell?.lblAvailableGames.text = "\(gameType.gameCount) games"
            } else {
                cell?.lblAvailableGames.text = "No games"
            }
        } else {
            cell?.lblAvailableGames.text = "Retrieving games"
        }
        
        
        return cell!
    }
    
    override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        return Theme.GAME_TYPE_CELL_HEIGHT
    }

    
    //MARK: - User Defaults
    
    private func loadGameTypesFromUserDefaults() {
        
        var gameTypeArray: NSMutableArray = []
        
        if let gameTypeArrayFromDefaults = NSUserDefaults.standardUserDefaults().objectForKey("gameTypes") as? NSArray {
            gameTypeArray = gameTypeArrayFromDefaults.mutableCopy() as! NSMutableArray
            
            for gameType in gameTypeArray {
                self.gameTypes.append(GameType.deserializeGameType(gameType as! [String : String]))
            }
        }

    }
    
    private func saveGameTypesToUserDefaults() {
        
        let gameTypeArray: NSMutableArray = []
        
        for gameType in self.gameTypes {
            let serializedGameType = GameType.serializeGameType(gameType)
            gameTypeArray.addObject(serializedGameType)
        }
        
        NSUserDefaults.standardUserDefaults().setObject(gameTypeArray, forKey: "gameTypes")
        NSUserDefaults.standardUserDefaults().setObject(NSDate(), forKey: "gameTypePullTimeStamp")
    }
    
    
    //MARK: - Parse
    
    private func loadGameTypesFromParse() {
        
        let gameTypeQuery = PFQuery(className: "GameType")
        gameTypeQuery.findObjectsInBackgroundWithBlock { (objects, error) -> Void in
            if let gameTypeObjects = objects {
    
                self.gameTypes.removeAll(keepCapacity: true)
                
                for gameTypeObject in gameTypeObjects {
                    let gameType = GameTypeConverter.convertParseObject(gameTypeObject)
                    self.gameTypes.append(gameType)
                }
            }
            
            self.saveGameTypesToUserDefaults()
            self.tableView.reloadData()
        }
    }
    
    
    private func loadGameCounts() {
        
        for gameType in self.gameTypes {
            let gameTypeObject = PFObject(withoutDataWithClassName: "GameType", objectId: gameType.id)
            let gameQuery = PFQuery(className: "Game")
            gameQuery.whereKey("gameType", equalTo: gameTypeObject)
            gameQuery.whereKey("date", greaterThanOrEqualTo: NSDate().dateByAddingTimeInterval(-1.5 * 60 * 60))
            gameQuery.whereKey("date", lessThanOrEqualTo: NSDate().dateByAddingTimeInterval(2 * 7 * 24 * 60 * 60))
            
            let userGeoPoint = PFGeoPoint(latitude: (self.currentLocation?.coordinate.latitude)!, longitude: self.currentLocation!.coordinate.longitude)
            
            gameQuery.whereKey("location", nearGeoPoint:userGeoPoint, withinMiles:15.0)

            gameQuery.countObjectsInBackgroundWithBlock({ (count: Int32, error: NSError?) -> Void in
                    let gameCount = Int(count)
                    gameType.increaseGameCount(gameCount)
                self.gameCountLoaded = true
            })
            
            
        }
    }
    
    //MARK: - Location Manager Delegate

    func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        let location:CLLocationCoordinate2D = manager.location!.coordinate
        currentLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)
        
        if currentLocation != nil {
            locationManager.stopUpdatingLocation()
        }
        
        self.tableView.reloadData()
    }
    
    func setUsersCurrentLocation() {
        self.locationManager.requestWhenInUseAuthorization()
        
        if CLLocationManager.locationServicesEnabled() {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.startUpdatingLocation()
        }
    }
    

    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == SEGUE_SHOW_GAMES {
            let gamesViewController = segue.destinationViewController as! GameListViewController
            if let indexPath = self.tableView.indexPathForSelectedRow {
                gamesViewController.selectedGameType = gameTypes[indexPath.row]
                gamesViewController.gameTypes = self.gameTypes
            }
            gamesViewController.navigationItem.leftItemsSupplementBackButton = true
        } else if segue.identifier == SEGUE_SHOW_NEW_GAME {
            let navigationController = segue.destinationViewController as! UINavigationController
            let newGameTableViewController = navigationController.viewControllers.first as! NewGameTableViewController
            newGameTableViewController.gameTypes = self.gameTypes
        } else if segue.identifier == SEGUE_SHOW_MY_GAMES {
            let myGamesViewController = segue.destinationViewController as! MyGamesViewController
            myGamesViewController.gameTypes = self.gameTypes
        }
    }
    
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        performSegueWithIdentifier(SEGUE_SHOW_GAMES, sender: self)
    }
    

}
