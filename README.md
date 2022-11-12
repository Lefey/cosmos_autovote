# Cosmos forks autovote script
Script for telegram proposal notification, voting callbacks and auto voting as most.

Change params, add to crontab.
```
*/5 * * * * bash $HOME/status/vote.sh >> $HOME/status/vote.log 2>&1
```

