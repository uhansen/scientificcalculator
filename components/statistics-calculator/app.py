from wit_world import exports


class Statistics(exports.Statistics):
    def sum(self, numbers: list[float]) -> float:
        total = 0.0
        for n in numbers:
            total += n
        return total

    def avg(self, numbers: list[float]) -> float:
        if not numbers:
            return 0.0
        total = 0.0
        for n in numbers:
            total += n
        return total / len(numbers)
