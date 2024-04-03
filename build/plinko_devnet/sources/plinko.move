module plinko_devnet::plinko {
use std::vector as vec;
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::random::{Self, Random, RandomGenerator, new_generator};
    use sui::balance::{Self, Balance};

    // --------------- Constants ---------------
    const LOW_GAME_TYPE: u8 = 0;
    const MID_GAME_TYPE: u8 = 1;
    const HIGH_GAME_TYPE: u8 = 2;
    const FLOAT_PRECISION_U128: u128 = 100;

    const LOW_GAME: vector<u64> = vector[600u64, 135u64, 80u64, 50u64, 80u64, 135u64, 600u64];
    const MID_GAME: vector<u64> = vector[3000u64, 600u64, 150u64, 70u64, 40u64, 40u64, 70u64, 150u64, 600u64, 3000u64];
    const HIGH_GAME: vector<u64> = vector[10000u64, 1000u64, 300u64, 150u64, 100u64, 65u64, 40u64, 65u64, 100u64, 150u64, 300u64, 1000u64, 10000u64];
    
    // --------------- Errors ---------------

    const EInvalidGameType: u64 = 0; 
    const EInvalidRndLength: u64 = 1;
    const EInvalidStakeAmount: u64 = 2;

    // --------------- Events ---------------
    struct BallOutcome has store, copy, drop {
        ball_index: u64,
        ball_path: vector<u8>,
    }

    struct Outcome<phantom T> has copy, drop {
        player: address,
        pnl: u64,
        bet_size: u64,
        ball_count: u64,
        game_type: u8,
        results: vector<BallOutcome>,
        challenged: bool
    }

    // --------------- Name Tag ---------------
    struct Plinko has store, copy, drop {}

    // --------------- Objects ---------------

    struct AdminCap has key {
        id: UID,
    }

    struct House<phantom T> has key, store {
        id: UID,
        house_pool: Balance<T>
    }

    struct Game<phantom T> has key, store {
        id: UID,
        player: address,
        ball_count: u64,
        bet_size: u64,
        game_type: u8,
        start_epoch: u64,
        stake: Coin<T>,
    }

    // --------------- Constructor ---------------
    fun init(ctx: &mut TxContext) {
        let admin = tx_context::sender(ctx);
        let admin_cap = AdminCap { id: object::new(ctx) };
        transfer::transfer(admin_cap, admin);
    }

    public fun create_house<T>(
        stake: Coin<T>, 
        ctx: &mut TxContext
    ) {
        let stake = coin::into_balance(stake);

        let house = House<T> {
            id: object::new(ctx),
            house_pool: stake
        };
        transfer::share_object(house);
    }

    public fun house_balance<T>(house: &House<T>): u64 {
        balance::value(&house.house_pool)
    }

    // --------------- Game Funtions ---------------

    // Note that functions with randomness should be non-public entry functions so that it's not compostable within smart contracts
    entry fun play_game<T>(
        house: &mut House<T>,
        r: &Random,
        ball_count: u64,
        bet_size: u64,
        game_type: u8,
        stake: Coin<T>,
        ctx: &mut TxContext,
    ) {
        let stake_amount = coin::value(&stake);
        assert!(stake_amount == ball_count * bet_size, EInvalidStakeAmount);

        // TODO: assert house has enough balance to handle max capacity
        let stake_balance = coin::into_balance(stake);
        balance::join(&mut house.house_pool, stake_balance);

        let player = tx_context::sender(ctx);
        let generator = new_generator(r, ctx);
        let game_count = 0;
        let pnl = 0;
        let ball_outcomes = vector[];

        while (game_count < ball_count) {
            game_count = game_count + 1;
            let game_vec = get_plinko_config(game_type);
            let (path, ball_index) = get_ball_roll_and_path(game_vec, &mut generator);

            let multiplier = vec::borrow(&game_vec, ball_index);
            let curr_game_payout = mul(bet_size, *multiplier);

            pnl = pnl + curr_game_payout;

            vec::push_back(&mut ball_outcomes, BallOutcome { 
                ball_index,
                ball_path: path,
            });
        };

        // Pay user the amount from the house
        let payout_bal = balance::split(&mut house.house_pool, pnl);
        let payout_coin = coin::from_balance(payout_bal, ctx);
        transfer::public_transfer(payout_coin, player);

        event::emit(Outcome<T> {
            player,
            pnl,
            bet_size,
            ball_count,
            game_type,
            results: ball_outcomes,
            challenged: false
        });
    }

    // Function that given a game config return the ball path, and sum of the rolls which is the index
    fun get_ball_roll_and_path(
        game: vector<u64>,
        mut_generator: &mut RandomGenerator,
    ): (vector<u8>, u64) {
        let i = 0;
        let curr_sum = 0;
        let path = vector[];

        // Should only go up to n - 1 levels total
        while (i < vec::length(&game) - 1) {
            i = i + 1;
            // This gives us modulo 2
            let random_number = random::generate_u8_in_range(mut_generator, 0, 1);
            curr_sum = curr_sum + (random_number as u64);
            vec::push_back(&mut path, (random_number));
        };
        (path, curr_sum)
    }

    // 0 - 6 levels
    // 1 - 9 levels
    // 2 - 12 levels
    fun get_plinko_config(game_type: u8) : vector<u64> {
        assert!(game_type == LOW_GAME_TYPE || game_type == MID_GAME_TYPE || game_type == HIGH_GAME_TYPE, EInvalidGameType);

        if (game_type == LOW_GAME_TYPE) {
            return LOW_GAME
        } else if (game_type == MID_GAME_TYPE) {
            return MID_GAME
        };
        HIGH_GAME
    }

    fun mul(x: u64, y: u64): u64 {
        (((x as u128) * (y as u128) / FLOAT_PRECISION_U128) as u64)
    }


    // --------------- Helper Funtions ---------------

    // Converts the first 16 bytes of rnd to a u128 number and outputs its modulo with input n.
    // Since n is u64, the output is at most 2^{-64} biased assuming rnd is uniformly random.
    public fun safe_selection(n: u64, rnd: &vector<u8>): u64 {
        assert!(vec::length(rnd) >= 16, EInvalidRndLength);
        let m: u128 = 0;
        let i = 0;
        while (i < 16) {
            m = m << 8;
            let curr_byte = *vec::borrow(rnd, i);
            m = m + (curr_byte as u128);
            i = i + 1;
        };
        let n_128 = (n as u128);
        let module_128  = m % n_128;
        let res = (module_128 as u64);
        res
    }

}