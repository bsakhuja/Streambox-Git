//
//  SongsViewController.swift
//  Streambox
//
//  Created by Brian Sakhuja on 7/7/17.
//  Copyright © 2017 Brian Sakhuja. All rights reserved.
//


import UIKit
import Foundation
import AVFoundation
import MediaPlayer
import NVActivityIndicatorView
import Fabric
import Crashlytics

class SongsViewController: UIViewController, NVActivityIndicatorViewable, AVAudioPlayerDelegate, UIToolbarDelegate, UISearchBarDelegate
{
    
    // Items array from the select folders view.  Converted into song objects
    var items = [Item]()
    {
        didSet
        {
            tableView.reloadData()
        }
    }
    
    // Song data types that are displayed in the table view controller
    var filteredSongs = songs
    
    // Utility variables for ensuring that the user can't download a song that they're already playing
    var indexPathOfFirstSong: IndexPath?
    var selectedSongIndexPath: IndexPath?
    var lastSongIndexPath: IndexPath?
    
    // Variables for song controls
    var previousIndexPath: IndexPath?
    var nextIndexPath: IndexPath?
    
    // MARK: - Table View
    @IBOutlet weak var tableView: UITableView!
    
    // MARK: - Search Bar
    @IBOutlet weak var searchbar: SearchSongsBar!
    let searchController = UISearchController(searchResultsController: nil)
    
    // MARK: - Download progress view
    
    // MARK: - VC Lifecycle
    override func viewDidLoad()
    {
        super.viewDidLoad()
        songs = CoreDataHelper.retrieveSongs()
        self.tableView.reloadData()
        
        // Update colors and fonts
        // Swift 4 updated
        self.navigationItem.backBarButtonItem?.tintColor = UIColor.white
        self.navigationController?.navigationBar.titleTextAttributes = [ NSAttributedStringKey.font: UIFont(name: "Lato-Regular", size: 20)!]
        
        
        // Used for loading songs in from the add folders view controller
        NotificationCenter.default.addObserver(forName: Notification.Name("DoneInitializing"), object: nil, queue: nil) { (notification) in
            print("notification is \(notification)")
            
            self.reloadSongs()
            
            DispatchQueue.main.async {
                self.tableView.reloadData()
                
                // hide activity indicator
                self.stopAnimating()
            }
        }
        
        // Get rid of extra separators by adding a view below
        self.tableView.tableFooterView = UIView()
        
        tableView.dataSource = self
        searchbar.delegate = self
        
        
    }
    
    override func didReceiveMemoryWarning()
    {
        super.didReceiveMemoryWarning()
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        if SongPlayerHelper.isSongLoaded
        {
            // Updates the slider position regularly at the specified interval
            Timer.scheduledTimer(timeInterval: 0.5, target: self,  selector: #selector(self.updateTime), userInfo: nil, repeats: true)
            
        }
        tableView.reloadData()
    }
    
    func reloadSongs()
    {
        SongPlayerHelper.songQueue.append(contentsOf: songs)
        
        Song.initializeSongs(from: items)
        songs = CoreDataHelper.retrieveSongs()
        filteredSongs = songs
    }
    
    // Called when 'Done' tapped in SelectFoldersViewController
    @IBAction func unwindToSongsViewController(_ segue: UIStoryboardSegue)
    {
        if items.count != 0
        {
            // show activity indicator
            startAnimating(CGSize(width: 50, height: 50), type: .ballClipRotate)
        }
        // make songs
        self.reloadSongs()
        tableView.reloadData()
    }
    
}



extension SongsViewController: UITableViewDataSource, UITableViewDelegate {
    
    // Number of rows in section
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int
    {
        // If there are no songs, the default message is shown
        if songs.count == 0
        {
            return 1
        }
        else
        {
            return filteredSongs.count
        }
    }
    
    // The height of the songs cells
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if songs.count == 0
        {
            return 65
        }
        else
        {
            return 55
        }
        
    }
    
    // Populate tableview
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell
    {
        
        // If there are no songs, the default message is shown
        if songs.count == 0
        {
            // Disable search for default message
            searchbar.isUserInteractionEnabled = false
            
            // Initial cell
            let cell = tableView.dequeueReusableCell(withIdentifier: "songSongCell") as! SongsTableViewCell
            let text = "Add songs from your Dropbox by tapping the + icon"
            cell.songArtistLabel.alpha = 0
            cell.isUserInteractionEnabled = false
            cell.downloadProgressBar.alpha = 0
            cell.songTitleLabel.text = text
            cell.songTitleLabel.numberOfLines = 2
            return cell
        }
        else
        {
            // Reenable search interaction
            searchbar.isUserInteractionEnabled = true
            
            // Populate table view with the songs
            let cell = tableView.dequeueReusableCell(withIdentifier: "songSongCell") as! SongsTableViewCell
            let text = filteredSongs[indexPath.row].title
            let song = filteredSongs[indexPath.row]
            cell.correspondingSong = filteredSongs[indexPath.row]
            cell.downloadProgressBar.alpha = 1
            cell.isUserInteractionEnabled = true
            cell.downloadProgressBar.height = 50.0
            cell.downloadProgressBar.progress = 0
            cell.songArtistLabel.alpha = 1
            cell.songTitleLabel.text = text
            cell.songTitleLabel.numberOfLines = 1
            
            if song.isDownloading
            {
                cell.downloadProgressBar.progress = song.downloadPercent
            } else
            {
                cell.downloadProgressBar.alpha = 0
            }
            
            if indexPath.row == 0
            {
                indexPathOfFirstSong = indexPath
            }
            
            // update the song artist label
            if song.artist != nil
            {
                cell.songArtistLabel.text = song.artist
            }
            
            // Update the song artwork
            if song.artwork != nil
            {
                cell.artworkImageView.image = UIImage(data: song.artwork! as Data)
            }
            else
            {
                cell.artworkImageView.image = #imageLiteral(resourceName: "white")
            }
            
            return cell
        }
    }
    
    // Song selected in the songs table view
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath)
    {
        // Set the song queue to the displayed songs when a user selects a cell
        SongPlayerHelper.songQueue = self.filteredSongs
        
        
        // Set the selected row to the row the user taps
        self.selectedSongIndexPath = indexPath
        
        let selectedCell = tableView.cellForRow(at: self.selectedSongIndexPath!) as? SongsTableViewCell
        
        if self.lastSongIndexPath != self.selectedSongIndexPath
        {
            if let previousRow = self.lastSongIndexPath
            {
                let previousCell = tableView.cellForRow(at: previousRow) as? SongsTableViewCell
                
                if SongPlayerHelper.isSongDownloading
                {
                    // cancel download of previous file
                    cancelDownload(forSongAt: filteredSongs[previousRow.row].filePath!)
                    
                    // Hide and reset the progress bar for the previous cell
                    previousCell?.downloadProgressBar.progress = 0.0
                    previousCell?.downloadProgressBar.alpha = 0.0
                }
                
            }
            
            previousIndexPath = IndexPath(row: indexPath.row - 1 , section: indexPath.section)
            nextIndexPath = IndexPath(row: indexPath.row + 1, section: indexPath.section)
            
            // Play the desired song song
            self.lastSongIndexPath = indexPath
            prepareForPlaySong(index: indexPath.row, songCell: selectedCell!)
        }
        
    }
    
    
    // Deleting songs
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if filteredSongs.count > 1
        {
            if editingStyle == .delete
            {
                CoreDataHelper.deleteSong(song: filteredSongs[indexPath.row])
                songs = CoreDataHelper.retrieveSongs()
                filteredSongs = songs
                tableView.deleteRows(at: [indexPath], with: .middle)
                Answers.logCustomEvent(withName: "Song Deleted From Library", customAttributes: nil)
                
                DispatchQueue.main.asyncAfter(deadline: .now(), execute: {
                    tableView.reloadData()
                })
                
            }
        }
    }
    
    // Cancel the download of the song at the given filepath
    func cancelDownload(forSongAt filePath: String)
    {
        DropboxHelper.cancelDownloadingFile(directory: filePath, onCompletion: { () in
            
        })
    }
    
    func prepareForPlaySong(index: Int, songCell: SongsTableViewCell)
    {
        // Set the selected song to the row the user tapped
        let selectedSong = filteredSongs[index]
        let downloadProgress = songCell.downloadProgressBar
        let path: String?
        // Present the progress bar and set the progress to 0
        downloadProgress?.alpha = 1.0
        downloadProgress?.progress = 0
        

        
        if (selectedSong.id?.hasPrefix("id:"))!
        {
            path = selectedSong.id
        }
        else
        {
            path = "id:" + (selectedSong.id)!
        }
        
        // Set the is downloading states to true
        SongPlayerHelper.isSongDownloading = true
        selectedSong.isDownloading = true
        
        DropboxHelper.downloadFileAsURL(song: selectedSong, directory: path ?? "", progressBar: (downloadProgress)!, onCompletion: { (downloadedSongURL) in
            
            // set the song player helper's current song info
            SongPlayerHelper.currentSongURL = downloadedSongURL
            SongPlayerHelper.currentSong = selectedSong
            
            // Update the id3 tags
            SongPlayerHelper.getID3Tags()

            
            self.tableView.reloadData()
            
            // Set the is downloading states to false
            SongPlayerHelper.isSongDownloading = false
            selectedSong.isDownloading = false
            
            SongPlayerHelper.currentSongIndexInQueue = (self.selectedSongIndexPath?.row)!
            
            selectedSong.title = SongPlayerHelper.currentSongTitle
            selectedSong.artist = SongPlayerHelper.currentSongArtist
            selectedSong.artwork = UIImagePNGRepresentation(SongPlayerHelper.currentSongArtwork!)!
            
            // show in now playing info center
            SongPlayerHelper.updateNowPlayingInfoCenter()
            
            self.playSongAsURL(songURL: downloadedSongURL!)
            
        })
        
    }
    
    
    func prepareForPlaySongInitial(songQueue: [Song])
    {
        // Set the selected song to the row the user tapped
        let selectedSong = filteredSongs[0]
        let songCell = tableView.cellForRow(at: indexPathOfFirstSong!) as? SongsTableViewCell
        let downloadProgress = songCell?.downloadProgressBar
        self.selectedSongIndexPath = indexPathOfFirstSong
        self.lastSongIndexPath = indexPathOfFirstSong
        
        SongPlayerHelper.currentSongTitle = selectedSong.title
        
        let path = "id:" + selectedSong.id!
        
        // Set the is downloading states to true
        SongPlayerHelper.isSongDownloading = true
        selectedSong.isDownloading = true
        
        DropboxHelper.downloadFileAsURL(song: selectedSong, directory: path, progressBar: (downloadProgress)!, onCompletion: { (downloadedSongURL) in
            // set the song player helper's current song info
            SongPlayerHelper.currentSongURL = downloadedSongURL
            SongPlayerHelper.currentSong = selectedSong

            
            // Set the is downloading states to false
            SongPlayerHelper.isSongDownloading = false
            selectedSong.isDownloading = false
            
            SongPlayerHelper.currentSongIndexInQueue = (self.selectedSongIndexPath?.row)!
            self.playSongAsURL(songURL: downloadedSongURL!)
            
        })
        
    }

    // Function that handles playing the song with AVAudioPlayer
    func playSongAsURL(songURL: URL)
    {
        
        do {
            // sets the default image to pause since the player presents itself when a song is playing
            SongPlayerHelper.audioPlayer = try AVAudioPlayer(contentsOf: songURL)
            SongPlayerHelper.audioPlayer.delegate = self
            SongPlayerHelper.audioPlayer.prepareToPlay()
            
            
            
            
//            // Updates the slider position regularly at the specified interval
//            Timer.scheduledTimer(timeInterval: 0.05, target: self,  selector: #selector(self.updateTime), userInfo: nil, repeats: true)
            
            // Play song
            SongPlayerHelper.isSongLoaded = true
            SongPlayerHelper.audioPlayer.play()
            Answers.logCustomEvent(withName: "Song Played", customAttributes: nil)
            
            // This block of code allows the user to listen to music in the background
            do {
                try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback, with: .mixWithOthers)
                //print("AVAudioSession Category Playback OK")
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    //print("AVAudioSession is Active")
                } catch {
                    print(error)
                }
            } catch {
                print(error)
            }
        } catch {
            print("error playing file")
        }
        
    }

    // Convert to minutes and seconds
    func secondsToMinutesSeconds (seconds : Int) -> (Int, Int) {
        return ((seconds % 3600) / 60, (seconds % 3600) % 60)
    }
    
    // Utility function for the slider
    @objc func updateTime(_ timer: Timer)
    {
        // Update the time labels
        let (minElapsed, secElapsed) = secondsToMinutesSeconds(seconds: Int(SongPlayerHelper.audioPlayer.currentTime))
        let (minRemaining, secRemaining) = secondsToMinutesSeconds(seconds: (Int(SongPlayerHelper.audioPlayer.duration-SongPlayerHelper.audioPlayer.currentTime)))
    }
    
    
    // Utility function for implementing search functionality
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String)
    {
        filteredSongs = searchText.isEmpty ? songs : songs.filter { (item: Song) -> Bool in
            return item.title?.range(of: searchText, options: .caseInsensitive, range: nil, locale: nil) != nil
        }
        
        tableView.reloadData()
    }
}
