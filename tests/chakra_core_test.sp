#pragma semicolon 1
#pragma newdecls required

#include <shell>
#include "../addons/sourcemod/scripting/include/chakra_core.inc"

int g_Checks;

void Expect(bool condition, const char[] message)
{
    g_Checks++;
    if (!condition)
    {
        print(message);
        report_error();
    }
}

bool Near(float actual, float expected)
{
    float delta = actual - expected;
    return delta > -0.001 && delta < 0.001;
}

public int main()
{
    ChakraPool pool;
    pool.Reset(100.0);
    Expect(Near(pool.amount, 100.0), "A new map starts at full chakra");
    for (int cast = 0; cast < 4; cast++)
    {
        Expect(pool.Reserve(25.0, 10.0, 5.0), "Four full-strength casts must be affordable");
        Expect(!pool.Reserve(25.0, 10.1, 5.0), "Cannot reserve a second overlapping cast");
        pool.Commit();
    }
    Expect(Near(pool.amount, 0.0), "Four casts use the full pool");
    Expect(!pool.Reserve(25.0, 11.0, 5.0), "A fifth cast must fail without going negative");
    Expect(Near(pool.amount, 0.0), "A rejected cast must not debit chakra");

    pool.Regenerate(4.0, 14.0, 1.0);
    Expect(Near(pool.amount, 0.0), "No regeneration during delay");
    pool.Regenerate(1.0, 15.25, 1.0);
    Expect(Near(pool.amount, 0.25), "A tick crossing the delay only credits elapsed eligible time");
    pool.Regenerate(24.75, 40.0, 1.0);
    Expect(Near(pool.amount, 25.0), "One chakra per second funds the next cast");
    Expect(pool.Reserve(25.0, 40.0, 5.0), "Regenerated chakra can be spent");
    pool.Regenerate(10.0, 50.0, 1.0);
    Expect(Near(pool.amount, 0.0), "No regeneration during preparation");
    pool.Cancel();
    pool.Cancel();
    Expect(Near(pool.amount, 25.0), "Cancellation refunds exactly once");

    pool.SetMaximum(10.0);
    Expect(Near(pool.amount, 10.0), "A smaller maximum clamps the current pool");
    Expect(pool.Reserve(10.0, 50.0, 0.0), "Can reserve the entire reduced pool");
    pool.SetMaximum(5.0);
    pool.Cancel();
    Expect(Near(pool.amount, 5.0), "Refund respects a changed maximum");
    pool.Regenerate(1000.0, 1050.0, 1.0);
    Expect(Near(pool.amount, 5.0), "Regeneration cannot overfill the pool");
    Expect(!pool.Reserve(0.0, 1050.0, 0.0), "Zero-cost reservations are rejected");
    Expect(!pool.Reserve(-1.0, 1050.0, 0.0), "Negative costs cannot grant chakra");

    Expect(Near(ChakraBlastDamage(0.0, 500.0, 300.0), 300.0), "Center receives full damage");
    Expect(Near(ChakraBlastDamage(250.0, 500.0, 300.0), 202.5), "Mid-radius damage remains substantial");
    Expect(Near(ChakraBlastDamage(500.0, 500.0, 300.0), 105.0), "Edge remains lethal to ordinary infected");
    Expect(Near(ChakraBlastDamage(500.01, 500.0, 300.0), 0.0), "Targets outside the blast are untouched");
    Expect(Near(ChakraBlastDamage(1.0, 0.0, 300.0), 0.0), "Invalid radius cannot divide by zero");
    Expect(Near(ChakraBlastDamage(-1.0, 500.0, 300.0), 0.0), "Invalid distances do not amplify damage");
    printf("PASS: %d gameplay assertions\n", g_Checks);
    return 0;
}
