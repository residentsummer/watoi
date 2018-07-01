# Whatsapp Android To iOS Importer

Migrate Whatsapp chats history from Android to iOS.

## Caveats

* Media files and shared locations are not imported (got placeholders instead)
* Messages from contacts that changed ids (phone numbers) are not linked

## Prerequisites

* Mac with installed Xcode and iTunes
* Decrypted `msgstore.db` from Android
* Installed and activated Whatsapp on your iDevice
* `Whatsapp.ipa` of the same version (google will help)

## Step-by-step guide

* Check that Whatsapp is activated on iDevice. You should see the list of *group* chats
  when you open the app. Most likely, there won't be any messages prior to moving to iOS.
  You can even send/receive a message or two to be sure that there is something to back up.
* Build the migration utility (I'll assume `~/Downloads` folder):

      cd ~/Downloads
      git clone https://github.com/residentsummer/watoi
      cd watoi
      xcodebuild -project watoi.xcodeproj -target watoi

* Create an unencrypted backup to local computer (not iCloud) with iTunes.
  Find the latest backup in `~/Library/Application Support/MobileSync/Backup`.
* Locate Whatsapp database file inside the backup and copy it somewhere:

      $ sqlite3 <backup>/Manifest.db "select fileID from Files where relativePath = 'ChatStorage.sqlite' and domain like '%whatsapp%';"
      abcdef01234567890
      $ cp <backup>/ab/abcdef01234567890 ~/Downloads/watoi/ChatStorage.sqlite

* Extract the contents of `Whatsapp.ipa` (we'll need CoreData description files):

      cd ~/Downloads/watoi
      unzip ~/Downloads/WhatsApp_Messenger_x.y.z.ipa -d app

* Backup original database and run the migration:

      cp ChatStorage.sqlite ~/Documents/SafePlace/
      build/Release/watoi <path-to-msgstore.db> ChatStorage.sqlite app/Payload/WhatsApp.app/WhatsAppChat.momd

* Replace database file inside the backup with the updated one:

      cp ChatStorage.sqlite "~/Library/Application Support/MobileSync/Backup/<backup>/ab/abcdef01234567890"

* Restore the backup with iTunes

## Troubleshooting

[![Gitter](https://badges.gitter.im/gitterHQ/gitter.svg)](https://gitter.im/residentsummer_watoi/Lobby?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)

## More TODOs

* Automate backup editing (skip manual ChatStorage locate/extract/replace)
* Better command-line parsing (better than none)
