# gpass
A GPG based password/secret manager that stores secrets in entries that store key-value pairs encrypted by GPG.
As opposed to [password store](http://www.passwordstore.org/), gpass does the following:

* Doesn't leak information about _what_ you store from file names, all files have randomly generated names.
* Allows use of symmetric (passphrase based) encryption, so you don't have to be afraid of losing your private key file.

# Installation
* Have a recent Ruby installation on your path
* make sure you have gnupg installed
* gem install gpgme
* Put the gpass shell script on your path and make sure it is executable

# Usage

#### Initialise repository

    gpass init

#### Add a new password entry (with a randomly generated password)

    gpass new [entry-name] [pwd-length] [optional-username]

#### Add more fields an entry

    gpass add [entry-name] [key] [value]

#### update a field an entry

    gpass add [entry-name] [key] [value]

#### Show password for an individual entry

    gpass pass [entry-name]

#### Show all values for an individual entry

    gpass show [entry-name]

#### Copy password into clipboard for an individual entry

    gpass clip [entry-name]

#### Search for an entry in the repository

    gpass search [part-of-entry-name]

#### Import exported 1Password csv file
This only works on the default csv export fields, with headers exported as well:

    gpass import1password [1password-csv-filename]



# TODO
* clipboard for Linux & Windows (win: echo foobar > /dev/clipboard)
* Remove entry
* Remove key for entry
* Change init to take settings (symmetric, or recipients)
* Public key encryption
* re-encrypt: change passphrase or encrypt for new recipients
