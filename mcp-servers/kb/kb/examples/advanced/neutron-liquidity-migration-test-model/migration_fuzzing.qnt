module migration_fuzzing {    
    import types.* from "types"
    import basicSpells.* from "basicSpells"

    // constants
    pure val USER_NAMES = Set("Alice", "Bob", "Charlie")
    pure val AMOUNTS = Set(2000, 30000, 400000, 5000000)

    // state variables
    var users: Addr -> UserData
    var stepInfo: StepInfo 
    var numSteps: int

    action init: bool =
        val emptyMsgInfo = {sender: ""}
        val userFundsMaps = USER_NAMES.setOfMaps(AMOUNTS)
        nondet usersNTRNLocked = userFundsMaps.oneOf()
        nondet usersATOMLocked = userFundsMaps.oneOf()
        nondet usersUSDCLocked = userFundsMaps.oneOf()
        val userBoolMaps = USER_NAMES.setOfMaps(Set(true, false))
        nondet usersOnlyVesting = userBoolMaps.oneOf()
        all {            
            stepInfo' = {
                actionTaken: "init",
                msgInfo: emptyMsgInfo,
                msgArgs: InitArgs(USER_NAMES.mapBy(
                    name => {
                        NTRN_locked: usersNTRNLocked.get(name),
                        ATOM_locked: usersATOMLocked.get(name),
                        USDC_locked: usersUSDCLocked.get(name)
                    })
                ),
                actionSuccessful: true,
                actionErrorDescription: ""
            },
                        
            users' = USER_NAMES.mapBy(
                name => {                                                         
                    migrated: false,
                    xyk_liquidity_withdrawn: false,
                    xyk_liquidity_withdrawn_before_migration: false,
                    pcl_liquidity_withdrawn: false,
                    has_xyk_rewards: true,
                    has_pcl_rewards: false,
                    only_vesting: usersOnlyVesting.get(name)
                }
            ),
            numSteps' = 0 

        }


    action claim_rewards_xyk(msg_info: MsgInfo, withdraw: bool): bool = 
        val actionTaken = "claim_rewards_xyk"
        val msgInfo = msg_info
        val msgArgs = ClaimRewardsArgs({withdraw: withdraw})
        all {
            // the user is still in the XYK pool
            require(users.get(msg_info.sender).migrated == false),
            // the user is in the lokcdrop (not only vesting)
            require(users.get(msg_info.sender).only_vesting == false),
            any{
                // if no claim is happening
                all{
                    require(
                        // no rewards and not trying to withdraw
                        (users.get(msg_info.sender).has_xyk_rewards == false and withdraw == false)
                        or 
                        // no liquidity at all, alredy withdrawn
                        users.get(msg_info.sender).xyk_liquidity_withdrawn == true),
                    users' = users.keys().mapBy(
                        addr  => {
                            has_pcl_rewards: and(
                                users.get(addr).migrated == true,
                                users.get(addr).pcl_liquidity_withdrawn==false
                                ),
                                ...users.get(addr)
                                }
                    ),
                    stepInfo' = {
                        actionTaken: actionTaken,
                        msgInfo: msgInfo,
                        msgArgs: msgArgs,
                        actionSuccessful: false,
                        actionErrorDescription: "User has already claimed rewards and does not withdraw"
                    }
                },
                // if it is possible to either withdraw or claim rewards
                all{
                    require(
                        users.get(msg_info.sender).has_xyk_rewards == true 
                        or
                        (users.get(msg_info.sender).xyk_liquidity_withdrawn == false and withdraw == true)
                        ),
                    val modifiedUsers = users.keys().mapBy(
                        addr  => {
                            has_pcl_rewards: and(
                                users.get(addr).migrated == true,
                                users.get(addr).pcl_liquidity_withdrawn==false
                                ),
                                ...users.get(addr)
                                }
                    )
                    users' = modifiedUsers.setBy(
                        msg_info.sender,
                        oldUserData => {                            
                            xyk_liquidity_withdrawn: withdraw,                            
                            has_xyk_rewards: false,
                            // once set to true, cannot go back to false
                            xyk_liquidity_withdrawn_before_migration: oldUserData.xyk_liquidity_withdrawn_before_migration or withdraw,
                            ...oldUserData
                        }),
                    stepInfo' = {
                        actionTaken: actionTaken,
                        msgInfo: msgInfo,
                        msgArgs: msgArgs,
                        actionSuccessful: true,
                        actionErrorDescription: ""
                    }                                
                }
            }
        } 

    action claim_rewards_pcl(msg_info: MsgInfo, withdraw: bool): bool = 
        val actionTaken = "claim_rewards_pcl"
        val msgInfo = msg_info
        val msgArgs = ClaimRewardsArgs({withdraw: withdraw})
        all {
            // the user has already migrated
            require(users.get(msg_info.sender).migrated == true),
            // the user is in the lockdrop contract, not only in the vesting
            require(users.get(msg_info.sender).only_vesting == false),
            any{
                // if no claim is happening
                all{
                    require(
                        // no rewards and not trying to withdraw
                        (users.get(msg_info.sender).has_pcl_rewards == false and withdraw == false)
                        or 
                        // no liquidity at all, alredy withdrawn
                        users.get(msg_info.sender).pcl_liquidity_withdrawn == true),
                    users' = users.keys().mapBy(
                        addr  => {
                            has_pcl_rewards: and(
                                users.get(addr).migrated == true,
                                users.get(addr).pcl_liquidity_withdrawn==false
                                ),
                                ...users.get(addr)
                                }
                    ),
                    stepInfo' = {
                        actionTaken: actionTaken,
                        msgInfo: msgInfo,
                        msgArgs: msgArgs,
                        actionSuccessful: false,
                        actionErrorDescription: "User has already claimed rewards and does not withdraw"
                    }
                },
                // if it is possible to either withdraw or claim rewards
                all{
                    require(
                        users.get(msg_info.sender).has_pcl_rewards == true 
                        or
                        (users.get(msg_info.sender).pcl_liquidity_withdrawn == false) and withdraw == true),
                    // since the transaction is happening, we set pcl rewards for the migrated users
                    val modifiedUsers = users.keys().mapBy(
                        addr  => {
                            has_pcl_rewards: and(
                                users.get(addr).migrated == true,
                                users.get(addr).pcl_liquidity_withdrawn==false
                                ),
                                ...users.get(addr)
                                }
                    )
                    users' = modifiedUsers.setBy(
                        msg_info.sender,
                        oldUserData => {                            
                            pcl_liquidity_withdrawn: withdraw,
                            has_pcl_rewards: false,
                            ...oldUserData
                        }),
                    stepInfo' = {
                        actionTaken: actionTaken,
                        msgInfo: msgInfo,
                        msgArgs: msgArgs,
                        actionSuccessful: true,
                        actionErrorDescription: ""
                    }                                
                }
            }
        }    

    
    action advance_block: bool = 
        all {
            // we do not want to have to consecutive block advances (no effect)
            require(stepInfo.actionTaken != "advance_block"),            
            stepInfo' = {
                actionTaken: "advance_block",
                msgInfo: {sender: ""},
                msgArgs: None,
                actionSuccessful: true,
                actionErrorDescription: ""
            },
            users' = users.keys().mapBy(
                addr => {                    
                    // if we did migrate to PCL, and the user did not withdraw liquidity from the relevant pool,
                    //  add rewards upon advancing a block                    
                    has_pcl_rewards: (users.get(addr).migrated == true and users.get(addr).pcl_liquidity_withdrawn == false),                        
                    ...users.get(addr)
                }
            )
        }
    
   
    action migrate(msg_info: MsgInfo, user_address: Addr): bool = 
        val user_to_migrate = if (user_address == "") msg_info.sender else user_address
        all{
            // not modelling this failure case
            require(users.get(user_to_migrate).migrated == false),
            any{
                all{
                    require(users.get(user_to_migrate).xyk_liquidity_withdrawn == false),
                    users' = users.setBy(
                        user_to_migrate,
                        oldUserData => {
                            migrated: true,                            
                            xyk_liquidity_withdrawn: true,                    
                            // at the very moment of migration, there are no rewards in the new  pool
                            has_pcl_rewards: false,
                            // we now sent all rewards to the user
                            has_xyk_rewards: false,
                            ...oldUserData
                        }),
                    stepInfo' = {
                        actionTaken: "migrate",
                        msgInfo: msg_info,
                        msgArgs: MigrateArgs({user_address: user_address}),
                        actionSuccessful: true,
                        actionErrorDescription: ""
                    }
                },
                all{
                    // if all was withdrawn so nothing to migrate
                    require(users.get(user_to_migrate).xyk_liquidity_withdrawn == true),
                    users' = users.setBy(
                        user_to_migrate,
                        oldUserData => {
                            migrated: false,
                            ...oldUserData
                        }),
                    stepInfo' = {
                        actionTaken: "migrate",
                        msgInfo: msg_info,
                        msgArgs: MigrateArgs({user_address: user_address}),
                        actionSuccessful: false,
                        actionErrorDescription: "Funds already withdrawn, nothing to migrate"
                    }
                }
            }
        }
        
    

    action step = 
        all{
            numSteps' = numSteps + 1,
            nondet senderName = USER_NAMES.oneOf()
            val msg_info = {sender: senderName}
            nondet doWithdrawXYK = Set(true, false).oneOf()        
            nondet doWithdrawPCL = Set(true, false).oneOf()
            nondet userToMigrate = USER_NAMES.union(Set("")).oneOf()
            any {
                claim_rewards_xyk(msg_info, doWithdrawXYK),
                advance_block,
                claim_rewards_pcl(msg_info, doWithdrawPCL),

                val user_address = userToMigrate
                migrate(msg_info, user_address)
            }
        }

    

    // invariant style testing: make sure that all users are migrated in the end
    val DESIRED_NUMBER_OF_STEPS = 15
    val fullMigrationHappened_inv = all {
        numSteps > DESIRED_NUMBER_OF_STEPS,
        users.keys().forall(
            addr => 
            (users.get(addr).only_vesting == false
            and
            users.get(addr).xyk_liquidity_withdrawn_before_migration == false)
            implies
            users.get(addr).migrated == true
            )
    }

    val fullMigrationHappened = not(fullMigrationHappened_inv)

    val allPCLLiquidityWithdrawn_inv = all {
        numSteps > DESIRED_NUMBER_OF_STEPS,
        users.keys().forall(
            addr => 
            (users.get(addr).only_vesting == false
            and
            users.get(addr).xyk_liquidity_withdrawn_before_migration == false)
            implies
            users.get(addr).pcl_liquidity_withdrawn == true
            )
    }

    // invariant to make sure that xyk_liquidity_withdrawn and xyk_liquidity_withdrawsn
    // are the same until the migration happens
    val xykLiquidityMigrationConsistent = users.keys().forall(
        addr => 
        users.get(addr).migrated == false
        implies
        users.get(addr).xyk_liquidity_withdrawn == users.get(addr).xyk_liquidity_withdrawn_before_migration
        )
    val allPCLLiquidityWithdrawn = not(allPCLLiquidityWithdrawn_inv)

    val largeNumberOfSteps_inv = numSteps > 20
    val largeNumberOfSteps = not(largeNumberOfSteps_inv)
  

}