[![Gem Version](https://badge.fury.io/rb/in_our_time.svg)](https://badge.fury.io/rb/in_our_time)

## In Our Time

Select, automatically download, and play **BBC In Our Time** podcasts easily, from the command line.

- [BBC In Our Time](http://www.bbc.co.uk/programmes/b006qykl).

Podcast is archived locally for offline access in the future.

Regularly checks for new podcasts.

- Light Theme

![compile image](https://raw.githubusercontent.com/mjago/In_Our_Time/master/images/light_theme.png)

- Dark Theme

![compile image](https://raw.githubusercontent.com/mjago/In_Our_Time/master/images/dark_theme.png)

## Installation:

```sh
gem install in_our_time
iot
```
## Config:

Config can be found at '~/.in_our_time/config.yml'

## mp3 player:

By default uses **afplay** as the media player but gains **Forward skip**, **Reverse Skip**, **Pause** and **Resume** controls when used with [mpg123](https://www.mpg123.de/). Install **mpg123** and modify the config.yml file to use **mpg123**:

```sh
:mpg_player: :mpg123
```

## Command line options:
Version:
```sh
iot --version
```
Help:
```sh
iot --help
```
