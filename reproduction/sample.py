class Calculator:
    def unused_method(self):
        """Method with no references."""
        return "never called"
    
    def add(self, a, b):
        """Method with 2 references."""
        return a + b
    
    def multiply(self, a, b):
        """Method with 3 references.""" 
        return a * b


# Create references
calc = Calculator()

# 2 references to add()
result1 = calc.add(1, 2)
result2 = calc.add(3, 4)

# 3 references to multiply()
result3 = calc.multiply(2, 3)
result4 = calc.multiply(4, 5)
result5 = calc.multiply(6, 7)