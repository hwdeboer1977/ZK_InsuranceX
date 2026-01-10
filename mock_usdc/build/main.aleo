program mock_usdc.aleo;

record Token:
    owner as address.private;
    amount as u128.private;

mapping balances:
    key as address.public;
    value as u128.public;

mapping total_supply:
    key as u8.public;
    value as u128.public;

mapping allowances:
    key as field.public;
    value as u128.public;

function mint_public:
    input r0 as address.public;
    input r1 as u128.public;
    assert.eq self.caller aleo1d9es6d8kuzg65dlfdpx9zxchcsarh8k0hwxfx5eg6k4w7ew6gs8sv5aza0;
    async mint_public r0 r1 into r2;
    output r2 as mock_usdc.aleo/mint_public.future;

finalize mint_public:
    input r0 as address.public;
    input r1 as u128.public;
    get.or_use balances[r0] 0u128 into r2;
    add r2 r1 into r3;
    set r3 into balances[r0];
    get.or_use total_supply[0u8] 0u128 into r4;
    add r4 r1 into r5;
    set r5 into total_supply[0u8];

function mint_private:
    input r0 as address.private;
    input r1 as u128.private;
    assert.eq self.caller aleo1d9es6d8kuzg65dlfdpx9zxchcsarh8k0hwxfx5eg6k4w7ew6gs8sv5aza0;
    cast r0 r1 into r2 as Token.record;
    output r2 as Token.record;

function transfer_public:
    input r0 as address.public;
    input r1 as u128.public;
    async transfer_public self.caller r0 r1 into r2;
    output r2 as mock_usdc.aleo/transfer_public.future;

finalize transfer_public:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u128.public;
    get balances[r0] into r3;
    gte r3 r2 into r4;
    assert.eq r4 true;
    sub r3 r2 into r5;
    set r5 into balances[r0];
    get.or_use balances[r1] 0u128 into r6;
    add r6 r2 into r7;
    set r7 into balances[r1];

function transfer_private:
    input r0 as Token.record;
    input r1 as address.private;
    input r2 as u128.private;
    gte r0.amount r2 into r3;
    assert.eq r3 true;
    cast r1 r2 into r4 as Token.record;
    sub r0.amount r2 into r5;
    cast r0.owner r5 into r6 as Token.record;
    output r4 as Token.record;
    output r6 as Token.record;

function approve:
    input r0 as address.public;
    input r1 as u128.public;
    async approve self.caller r0 r1 into r2;
    output r2 as mock_usdc.aleo/approve.future;

finalize approve:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u128.public;
    hash.bhp256 r0 into r3 as field;
    hash.bhp256 r1 into r4 as field;
    add r3 r4 into r5;
    set r2 into allowances[r5];

function transfer_from:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as u128.public;
    async transfer_from self.caller r0 r1 r2 into r3;
    output r3 as mock_usdc.aleo/transfer_from.future;

finalize transfer_from:
    input r0 as address.public;
    input r1 as address.public;
    input r2 as address.public;
    input r3 as u128.public;
    hash.bhp256 r1 into r4 as field;
    hash.bhp256 r0 into r5 as field;
    add r4 r5 into r6;
    get allowances[r6] into r7;
    gte r7 r3 into r8;
    assert.eq r8 true;
    sub r7 r3 into r9;
    set r9 into allowances[r6];
    get balances[r1] into r10;
    gte r10 r3 into r11;
    assert.eq r11 true;
    sub r10 r3 into r12;
    set r12 into balances[r1];
    get.or_use balances[r2] 0u128 into r13;
    add r13 r3 into r14;
    set r14 into balances[r2];

function burn_public:
    input r0 as u128.public;
    async burn_public self.caller r0 into r1;
    output r1 as mock_usdc.aleo/burn_public.future;

finalize burn_public:
    input r0 as address.public;
    input r1 as u128.public;
    get balances[r0] into r2;
    gte r2 r1 into r3;
    assert.eq r3 true;
    sub r2 r1 into r4;
    set r4 into balances[r0];
    get total_supply[0u8] into r5;
    sub r5 r1 into r6;
    set r6 into total_supply[0u8];

function transfer_pub_to_priv:
    input r0 as address.public;
    input r1 as u128.public;
    cast r0 r1 into r2 as Token.record;
    async transfer_pub_to_priv self.caller r1 into r3;
    output r2 as Token.record;
    output r3 as mock_usdc.aleo/transfer_pub_to_priv.future;

finalize transfer_pub_to_priv:
    input r0 as address.public;
    input r1 as u128.public;
    get balances[r0] into r2;
    gte r2 r1 into r3;
    assert.eq r3 true;
    sub r2 r1 into r4;
    set r4 into balances[r0];

function transfer_priv_to_pub:
    input r0 as Token.record;
    input r1 as address.public;
    input r2 as u128.public;
    gte r0.amount r2 into r3;
    assert.eq r3 true;
    sub r0.amount r2 into r4;
    cast r0.owner r4 into r5 as Token.record;
    async transfer_priv_to_pub r1 r2 into r6;
    output r5 as Token.record;
    output r6 as mock_usdc.aleo/transfer_priv_to_pub.future;

finalize transfer_priv_to_pub:
    input r0 as address.public;
    input r1 as u128.public;
    get.or_use balances[r0] 0u128 into r2;
    add r2 r1 into r3;
    set r3 into balances[r0];

constructor:
    assert.eq edition 0u16;
