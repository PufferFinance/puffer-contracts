contract Positive1 {
    address owner;

    function swap() public decorateSomeHow {
        int a = 2;
        uint before = tokenA.balanceOf(address(this));
        doSomething();
        uint after = tokenA.balanceOf(address(this));
        uint diff = after - before;
        int b = 3;
    }
}

contract Negative1 {
    address owner;

    function swap() public decorateSomeHow {
        int a = 2;
        uint before = tokenA.balanceOf(address(this));
        doSomething();
        uint after = tokenB.balanceOf(address(this));
        uint diff = after - before;
        int b = 3;
    }
}

contract Negative2 {
    address owner;

    function swap1() public {
        uint before = tokenA.balanceOf(address(this));
    }

    function swap() public decorateSomeHow {
        int a = 2;
        doSomething();
        uint after = tokenA.balanceOf(address(this));
        int b = 3;
    }
}

contract Negative3 {
    address owner;

    function swap() public something nonReentrant someDecorator {
        int a = 2;
        uint before = tokenA.balanceOf(address(this));
        doSomething();
        uint after = tokenA.balanceOf(address(this));
        uint diff = after - before;
        int b = 3;
    }
}