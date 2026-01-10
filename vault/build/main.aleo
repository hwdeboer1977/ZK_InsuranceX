program zk_insurancex.aleo;

mapping employers:
    key as address.public;
    value as boolean.public;

function register_employer:
    input r0 as address.private;
    assert.eq self.caller aleo1rhgdu77hgyqd3xjj8ucu3jj9r2krwz6mnzyd80gncr5fxcwlh5rsvzp9px;
    async register_employer r0 into r1;
    output r1 as zk_insurancex.aleo/register_employer.future;

finalize register_employer:
    input r0 as address.public;
    get.or_use employers[r0] false into r1;
    not r1 into r2;
    assert.eq r2 true;
    set true into employers[r0];

function is_employer:
    input r0 as address.private;
    async is_employer r0 into r1;
    output r1 as zk_insurancex.aleo/is_employer.future;

finalize is_employer:
    input r0 as address.public;
    get.or_use employers[r0] false into r1;
    assert.eq r1 true;

constructor:
    assert.eq edition 0u16;
