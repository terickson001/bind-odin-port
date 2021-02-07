#define foo(...) a, ##__VA_ARGS__

int main(void)
{
    int foo();
}