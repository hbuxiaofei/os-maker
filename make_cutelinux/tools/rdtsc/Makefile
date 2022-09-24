MOD := rdtsc
OBJ := $(MOD).bin

all: $(OBJ)

$(OBJ): $(MOD).c
	gcc -o $@ $^

clean:
	rm -rf $(OBJ)
