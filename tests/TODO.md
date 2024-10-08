NOTES: 
- tests have to be e2e - each test spawn its own instance of ascend/asctl and runs it independently, review logs
- tests should use eli scripts for portability
- there should be common function to setup environment for test before its run 

PREP:
- [x] test-env
    - [x] run - run ascend
    - [x] new - additional env, config etc. if needed

TESTS:
- [x] Core
    - [x] single module
        - [x] automatic start
        - [x] automatic start (2 services)
        - [x] manual start
        - [x] delayed start
        - [x] stop
        - [x] stop signal
        - [x] stop timeout (kill)
        - [x] restart always
            - [x] make sure it does NOT respects restart counters
        - [x] restart never
        - [x] restart on-exit
            - [x] make sure it respects restart counters
        - [x] restart on-failure
        - [x] restart on-success
        - [x] restart delay
        - [x] restart max retries
        - [x] default values
        - [x] working directory
    - [x] multi module
        - [x] automatic start
        - [x] manual start
        - [x] delayed start
        - [x] stop
        - [x] stop signal
        - [x] stop timeout (kill)
        - [x] restart always
            - [x] make sure it does NOT respects restart counters
        - [x] restart never
        - [x] restart on-exit
            - [x] make sure it respects restart counters
        - [x] restart on-failure
        - [x] restart on-success
        - [x] restart delay
        - [x] restart max retries
        - [x] default values
        - [x] global property propagation down to modules
        - [x] working directory
- [x] isolation
    - [x] user
    - [x] ascend slice
- [x] Health checks
    - [x] interval
    - [x] timeout
    - [x] retries
    - [x] delay
    - [x] action - none
    - [x] action - restart
- [x] Logs
    - [x] rotate
    - [x] simple file
    - [x] max size
    - [x] max files
- [x] asctl commands
    - [x] list
    - [x] list --extended
    - [x] stop
    - [x] stop only one module from multi module service
    - [x] start
    - [x] restart
    - [x] reload
    - [x] ascend-health
    - [x] status
    - [x] logs
    - [x] logs -f
    - [x] show
- [ ] advanced
    - [x] init - lua
    - [x] init - shell script
    - [ ] ami apps
    - [ ] ami bootstrap