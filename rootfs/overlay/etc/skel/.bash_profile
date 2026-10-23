# Login bash reads only the first of ~/.bash_profile, ~/.bash_login and
# ~/.profile, so this one reads the other two: settings in ~/.profile keep
# applying, and login and non-login shells share ~/.bashrc.
[ -f ~/.profile ] && . ~/.profile
[ -f ~/.bashrc ] && . ~/.bashrc
