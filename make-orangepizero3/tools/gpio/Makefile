
TARGET := gpio

SRC += gpio.c
SRC += wiringPi.c
SRC += readall.c

all: $(TARGET)


$(TARGET): $(SRC)
	$(CC) -o $@ $^

clean:
	rm -rf $(TARGET)

