#[test_only]
module plinko_devnet::test_play {
    use plinko_devnet::plinko::{Self, House, house_balance};
    use sui::sui::SUI;
    use sui::random;
    use sui::random::{Random, update_randomness_state_for_testing};
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{mint_for_testing};


    const BET_SIZE_ONE_SUI: u64 = 1000000000;
    const ADMIN: address = @0xde1;
    const ALICE: address = @0xAAAA;

    #[test_only]
    fun setup_for_testing(): Scenario {
        // Create house
        let scenario_val = ts::begin(ADMIN);
        let scenario = &mut scenario_val;
        ts::next_tx(scenario, ADMIN);
        {
            let stake = mint_for_testing<SUI>(
                BET_SIZE_ONE_SUI * 1000, 
                ts::ctx(scenario)
            );

            plinko::create_house<SUI>(
                stake,
                ts::ctx(scenario)
            );
        };
        scenario_val
    }

    #[test]
    fun test_plinko() {
        let scenario_val = setup_for_testing();
        let scenario = &mut scenario_val;
        // Admin for setup
        // Setup randomness
        ts::next_tx(scenario, @0x0);
        {
            random::create_for_testing(ts::ctx(scenario));
        };
        ts::next_tx(scenario, @0x0);
        {
            random::create_for_testing(ts::ctx(scenario));
            let random_state = ts::take_shared<Random>(scenario);
            update_randomness_state_for_testing(
                &mut random_state,
                0,
                x"1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F1F",
                ts::ctx(scenario),
            );
            ts::return_shared(random_state);
        };
        ts::next_tx(scenario, ALICE);
        let house = ts::take_shared<House<SUI>>(scenario);
        let random_state = ts::take_shared<Random>(scenario);
        let stake = mint_for_testing<SUI>(
            BET_SIZE_ONE_SUI * 100, 
            ts::ctx(scenario)
        );
        std::debug::print(&house_balance<SUI>(&house));
        plinko::play_game<SUI>(
            &mut house,
            &random_state,
            100,
            BET_SIZE_ONE_SUI,
            1,
            stake,
            ts::ctx(scenario)
        );
        std::debug::print(&house_balance<SUI>(&house));
        ts::return_shared(house);
        ts::return_shared(random_state);
        ts::end(scenario_val);

    }
}