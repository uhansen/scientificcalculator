namespace LogaritmicCalculatorWorld.wit.Exports.buildbyhansen.logaritmicCalculator.v0_1_0;

public class LogaritmicExportsImpl : ILogaritmicExports
{
    public static double E()
    {
        return Math.E;
    }

    public static double Ln(double x)
    {
        return Math.Log(x);
    }
}
