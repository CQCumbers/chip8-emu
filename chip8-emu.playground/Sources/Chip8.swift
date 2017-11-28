/*:
## CHIP8 Emulator
This project is based on the article by [multigesture](http://www.multigesture.net/articles/how-to-write-an-emulator-chip-8-interpreter/)
and the extensive documentation from [cowgod](http://devernay.free.fr/hacks/chip8/C8TECH10.HTM).

An emulator simulates the way a piece of computer hardware operates by mimicking its operation in software.
The Chip8 is a simple virtual machine designed to operate like a real physical CPU.
Like a CPU, it reads in a list of simple instructions (opcodes) stored in memory, and executes them very quickly (60 per second, in our case)
These instructions are things like moving a number from memory (RAM) to a register in the CPU,
or adding a number to the value of a register, or skipping the next instruction if two registers are equal, etc.
In addition, there are instructions for interacting with timers, an input keypad, and a black and white display.
*/

import UIKit
import PlaygroundSupport

final class Chip8 {
/*:
### Components
The Chip8 has 4KB (4096 bytes) of memory, 15 8-bit general purpose registers (`V0` to `VE`) plus a carry register (`VF`),
a 16 bit index register (`I`), and two 8-bit timers, for delay (`DT`) and sound (`ST`). Here, a byte is represented as an 8-bit unsigned integer type.
16 bits are used for storing memory addresses, so the index register, stack, and program counter, which store addresses, are 16-bit.
*/
    var memory = [UInt8](repeating: 0, count:4096) // memory
    var V = [UInt8](repeating: 0, count: 16) // CPU registers
    var I : UInt16 = 0 // special memory address register
    var DT : UInt8 = 0 // delay timer
    var ST : UInt8 = 0 // sound timer
    
/*:
The program counter (`pc`) keeps track of where the next instruction is located in memory.
It starts at `0x200` (512 in hexadecimal) because memory before that is reserved for a bitmap font set.
The stack and stack pointer used for keeping track of the addresses where a call to a subroutine was made,
so that they can be returned to after the subroutine finishes.
*/
    var pc : UInt16 = 0x200 // program counter
    var sp : UInt8 = 0 // stack pointer
    var stack = [UInt16](repeating: 0, count: 16) // stack
    
/*:
The display is 64 x 32 pixels, and each pixel can either be black or white.
In the original Chip8 each pixel would have been a bit in memory, but here each is a byte.
The keyboard has 16 keys, each with a different hexadecimal digit, that can either be pressed or not pressed.
The draw flag is used to keep track of whether the display has been updated.
When the draw flag is true, another program (the ViewController) takes the display bytes
stored in memory and shows the appropriate image to the screen.
*/
    var display = [UInt8](repeating: 0, count: 64 * 32) // display
    var keyboard = [Bool](repeating: false, count: 16) // keyboard
    var drawFlag : Bool = false // whether screen must be updated this cycle
    
/*:
### Memory
The first 80 bytes in memory are used for a bitmap font set.
Each bit is a pixel, and each character is 8x5 pixels, so every byte is a row and every 5 bytes is a new character.
You can see how the bytes map into characters below:

```
 Hex |   Binary | On Screen
---------------------------
0xF0   11110000   ****
0x90   10010000   *  *
0x90   10010000   *  *
0x90   10010000   *  *
0xF0   11110000   ****
```

The rest of the memory is used to store whatever program we want to run - In this case, we'll use Pong.
Generally, this is used to store the instructions that the CPU uses to run the program,
though programs can also store custom bitmap graphics and other data here, then reference them in their instructions.
*/
    // load application rom and fontset into memory
    init(rom: [UInt8]) {
        // load fontset into memory
        self.memory[..<80] = [
            0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
            0x20, 0x60, 0x20, 0x20, 0x70, // 1
            0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
            0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
            0x90, 0x90, 0xF0, 0x10, 0x10, // 4
            0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
            0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
            0xF0, 0x10, 0x20, 0x40, 0x40, // 7
            0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
            0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
            0xF0, 0x90, 0xF0, 0x90, 0x90, // A
            0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
            0xF0, 0x80, 0x80, 0x80, 0xF0, // C
            0xE0, 0x90, 0x90, 0x90, 0xE0, // D
            0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
            0xF0, 0x80, 0xF0, 0x80, 0x80  // F
        ]

        // load application ROM into memory
        self.memory[Int(self.pc)...] = rom[...]
    }
    
/*:
### CPU
Every second, a CPU fetches from memory, decodes, and follows many instructions.
Each time a single instruction is processed is a cycle. The Chip8 has a cycle speed of 60 Hz, meaning 60 instructions are processed a second.
The Chip8 CPU takes instructions in the form of 16-bit opcodes, which can be fetched from memory by concatenating two consecutive bytes.
*/
    // emulate one CPU cycle
    func emulateCycle() {
        // fetch 2 bytes from memory according to program counter, and concat to get next opcode
        let opcode : UInt16 = (UInt16(self.memory[Int(self.pc)]) << 8) | UInt16(self.memory[Int(self.pc+1)])

/*:
After fetching the opcode, the Chip8 CPU does different things depending on what it is. For example:

- If the opcode is `0x00E0`, the CPU knows to clear the display,
then increment the program counter (`pc`) to the address of the next opcode.
- If the opcode is of the form `0x1NNN`, where `NNN` is any 12-bit value, the CPU knows to set the program counter to the address `NNN`
- If the opcode is of the form `0x3XKK`, where `X` is any 4-bit value and `KK` is any 8-bit value,
the CPU knows to skip the next instruction (increment the program counter twice) if the value stored in the register `V[X]`
is equal to the value `KK` (and to increment `pc` once otherwise).
- If the opcode is of the form `0x8XY3`, the CPU knows to set register `V[x]` to `V[x] ^ V[y]`, where `^` is a bitwise XOR.
Many instructions require bit operations, so it's a good idea to have a clear understanding of what those are beforehand.

Most of the other instructions take a similar form - see [cowgod's instruction reference](http://devernay.free.fr/hacks/chip8/C8TECH10.HTM#3.0) for details.
*/
        // decode and execute opcode
        let x = Int((opcode & 0x0F00) >> 8)
        let y = Int((opcode & 0x00F0) >> 4)
        switch opcode {
            case 0x0000..<0x1000 where (y != 0xE): // SYS addr
                print("Machine code jump ignored")
                self.pc += 2
            case 0x00E0: // CLS
                self.display = self.display.map { _ in 0 }
                self.drawFlag = true
                self.pc += 2
            case 0x00EE: // RET
                self.sp -= 1
                self.pc = self.stack[Int(self.sp)] + 2
            case 0x1000..<0x2000: // JP addr
                self.pc = opcode & 0x0FFF
            case 0x2000..<0x3000: // CALL addr
                self.stack[Int(self.sp)] = self.pc
                self.sp += 1
                self.pc = opcode & 0x0FFF
            case 0x3000..<0x4000: // SE Vx, byte
                if (self.V[x] == (opcode & 0x00FF)) {
                    self.pc += 2
                }
                self.pc += 2
            case 0x4000..<0x5000: // SNE Vx, byte
                if (self.V[x] != (opcode & 0x00FF)) {
                    self.pc += 2
                }
                self.pc += 2
            case 0x5000..<0x6000 where (opcode & 0x000F == 0): // SE Vx, Vy
                if (self.V[x] == self.V[y]) {
                    self.pc += 2
                }
                self.pc += 2
            case 0x6000..<0x7000: // LD Vx, byte
                self.V[x] = UInt8(opcode & 0x00FF)
                self.pc += 2
            case 0x7000..<0x8000: // ADD Vx, byte
                self.V[x] = self.V[x] &+ UInt8(opcode & 0x00FF)
                self.pc += 2
            case 0x8000..<0x9000 where (opcode & 0x000F == 0x0): // LD Vx, Vy
                self.V[x] = self.V[y]
                self.pc += 2
            case 0x8000..<0x9000 where (opcode & 0x000F == 0x1): // OR Vx, Vy
                self.V[x] |= self.V[y]
                self.pc += 2
            case 0x8000..<0x9000 where (opcode & 0x000F == 0x2): // AND Vx, Vy
                self.V[x] &= self.V[y]
                self.pc += 2
            case 0x8000..<0x9000 where (opcode & 0x000F == 0x3): // XOR Vx, Vy
                self.V[x] ^= self.V[y]
                self.pc += 2
            case 0x8000..<0x9000 where (opcode & 0x000F == 0x4): // ADD Vx, Vy
                let result = self.V[x].addingReportingOverflow(self.V[y])
                (self.V[x], self.V[Int(0xF)]) = (result.0, result.1 ? 1 : 0)
                self.pc += 2
            case 0x8000..<0x9000 where (opcode & 0x000F == 0x5): // SUB Vx, Vy
                let result = self.V[x].subtractingReportingOverflow(self.V[y])
                (self.V[x], self.V[Int(0xF)]) = (result.0, result.1 ? 0 : 1)
                self.pc += 2
            case 0x8000..<0x9000 where (opcode & 0x000F == 0x6): // SHR Vx {, Vy}
                self.V[Int(0xF)] = self.V[x] & 0x01
                self.V[x] >>= 1
                self.pc += 2
            case 0x8000..<0x9000 where (opcode & 0x000F == 0x7): // SUBN Vx, Vy
                let result = self.V[y].subtractingReportingOverflow(self.V[x])
                (self.V[x], self.V[Int(0xF)]) = (result.0, result.1 ? 0 : 1)
                self.pc += 2
            case 0x8000..<0x9000 where (opcode & 0x000F == 0xE): // SHL Vx {, Vy}
                self.V[Int(0xF)] = self.V[x] & 0x80 >> 7
                self.V[x] <<= 1
                self.pc += 2
            case 0x9000..<0xA000 where (opcode & 0x000F == 0): // SNE Vx, Vy
                if (self.V[x] != self.V[y]) {
                    self.pc += 2
                }
                self.pc += 2
            case 0xA000..<0xB000: // LD I, addr
                self.I = opcode & 0x0FFF
                self.pc += 2
            case 0xB000..<0xC000: // JP addr + V0
                self.pc = UInt16(self.V[0]) + opcode & 0x0FFF
            case 0xC000..<0xD000: // RND Vx, byte
                self.V[x] = UInt8(arc4random_uniform(256)) & UInt8(opcode & 0x00FF)
                self.pc += 2
/*:
### Display
The Chip8 uses instructions of the form `0xDXYN` to specifiy how to draw sprites to the display.
Sprites should be stored at the memory address specified by the index register (`I`), and have width 8 and height `N`.
Sprites are like the fontset loaded earlier - each pixel is represented by a bit in memory.
Width is stored first, so the sprite in memory should be `N` bytes long.
The CPU reads the sprite from memory, and writes it to the display starting at row `V[Y]` and column `V[X]`
Each bit of the sprite is XORed with the existing pixel at the location it is to be written to,
and if this causes a pixel to be erased, `V[F]` is set to 0.
In addition, if part of a sprite is past the edge of the screen, it wraps around to the other side.
*/
            case 0xD000..<0xE000: // DRW Vx, Vy, nibble
                self.V[Int(0xF)] = 0
                for row in 0..<Int(opcode & 0x000F) {
                    let screen_row = (Int(self.V[y]) + row) % 32
                    let sprite_byte = self.memory[Int(self.I)+row]
                    for col in 0..<8 {
                        let screen_col = (Int(self.V[x])  + col) % 64
                        if (sprite_byte & (0x80 >> col) != 0) {
                            if (self.display[screen_row*64 + screen_col] != 0) {
                                self.V[Int(0xF)] = 1
                                self.display[screen_row*64 + screen_col] = 0
                            } else {
                                self.display[screen_row*64 + screen_col] = 0xFF
                            }
                        }
                    }
                }
                self.drawFlag = true
                self.pc += 2
            case 0xE000..<0xF000 where (opcode & 0x00FF == 0x9E): // SKP Vx
                if (self.keyboard[Int(self.V[x])] == true) {
                    self.pc += 2
                }
                self.pc += 2
            case 0xE000..<0xF000 where (opcode & 0x00FF == 0xA1): // SKNP Vx
                if (self.keyboard[Int(self.V[x])] == false) {
                    self.pc += 2
                }
                self.pc += 2
            case 0xF000...0xFFFF where (opcode & 0x00FF == 0x07): // LD Vx, DT
                self.V[x] = self.DT
                self.pc += 2
            case 0xF000...0xFFFF where (opcode & 0x00FF == 0x0A): // LD Vx, K
                if let i = self.keyboard.index(of: true) {
                    self.V[x] = UInt8(i)
                    self.pc += 2
                }
            case 0xF000...0xFFFF where (opcode & 0x00FF == 0x15): // LD DT, Vx
                self.DT = self.V[x]
                self.pc += 2
            case 0xF000...0xFFFF where (opcode & 0x00FF == 0x18): // LD ST, Vx
                self.ST = self.V[x]
                self.pc += 2
            case 0xF000...0xFFFF where (opcode & 0x00FF == 0x1E): // ADD I, Vx
                self.I += UInt16(self.V[x])
                self.pc += 2
            case 0xF000...0xFFFF where (opcode & 0x00FF == 0x29): // LD F, Vx
                self.I = UInt16(self.V[x] * 5)
                self.pc += 2
            case 0xF000...0xFFFF where (opcode & 0x00FF == 0x33): // LD B, Vx
                self.memory[Int(self.I)..<Int(self.I)+3] = [(self.V[x]/100), (self.V[x]/10)%10, self.V[x]%10]
                self.pc += 2
            case 0xF000...0xFFFF where (opcode & 0x00FF == 0x55): // LD [I], Vx
                self.memory[Int(self.I)...Int(self.I)+x] = self.V[...x]
                self.pc += 2
            case 0xF000...0xFFFF where (opcode & 0x00FF == 0x65): // LD Vx, [I]
                self.V[...x] = self.memory[Int(self.I)...Int(self.I)+x]
                self.pc += 2
            default:
                print(String(format:"unknown opcode: %X", opcode))
                self.pc += 2
        }
        
        // Debug code
        //print(String(format:"pc: %2X", self.pc))
        //print(String(format:"opcode: %2X", opcode))
        //print(String(format:"I: %2X", self.I))
        //print(self.V)
        /*if (self.drawFlag == true) {
            for row in 0..<32 {
                for col in 0..<64 {
                    print(self.display[row*64 + col] ? "*" : " ", terminator:"")
                }
                print("|")
            }
            print(String(repeating: "-", count: 64))
            chip8.drawFlag = false
        }*/
    }
    
/*:
### Timers
Lastly, the timers are decremented. These are supposed to count down at a constant rate of 60 Hz, which is the same as our cycle speed,
so we can just decrement each timer by one every clock cycle, as long as they are above 0.
*/
    @objc func updateTimers() {
        // Update timers
        if (self.DT > 0) { self.DT -= 1 }
        if (self.ST > 0) { self.ST -= 1 }
        
    }
}

/*:
### Display and keyboard for chip8 I/O
The following code is used for showing the chip8 display, represented as a series of bytes, as a UIImage on screen.
Each frame, a grayscale core graphics image (an immutable bitmap) is created from the bytes in memory representing the display,
and a UIImage is created from the CGImage. The containing UIImageView is then set to display on screen when next possible.
*/

final class DisplayView:UIView {
    let chip8:Chip8
    let width:Int
    let height:Int
    let colorSpace = CGColorSpaceCreateDeviceGray()
    
    init(frame: CGRect, chip: Chip8, width:Int, height:Int) {
        self.chip8 = chip
        self.width = width
        self.height = height
        super.init(frame:frame)
        self.layer.magnificationFilter = kCAFilterNearest
        self.refresh()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func refresh() {
        if (chip8.drawFlag == true) {
            guard let bitmapContext = CGContext(
                data: UnsafeMutableRawPointer(mutating: chip8.display),
                width: self.width,
                height: self.height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: self.colorSpace,
                bitmapInfo: 0x200),
            let cgImage = bitmapContext.makeImage()
            else { return }

            self.layer.contents = cgImage
            chip8.drawFlag = false
        }
    }
}

/*:
### Run whole thing inside of a view controller
The View Controller handles laying out the UI, including the display and keypad,
and processing button input before handing it off to the chip8
*/

public final class ViewController: UIViewController {
    var chip8:Chip8!
    var timer:Timer!
    var timer2:Timer!
    var displayView:DisplayView!
    
    override public func viewDidLoad() {
        super.viewDidLoad()

        let pong_url = Bundle.main.url(forResource: "breakout", withExtension: "rom")
        let pong = [UInt8] (try! Data(contentsOf: pong_url!))
        self.chip8 = Chip8(rom:pong)
        self.timer = Timer.scheduledTimer(timeInterval: 0.002, target: self, selector: #selector(runCycle), userInfo: nil, repeats: true)
        self.timer2 = Timer.scheduledTimer(timeInterval: 0.017, target: chip8, selector: #selector(Chip8.updateTimers), userInfo: nil, repeats: true)
        
        // UI and Layout
        let view = UIView(frame:CGRect(x:0, y:0, width:64*8, height:96*8))
        self.displayView = DisplayView(frame:CGRect(x:0, y:0, width:64*8, height:32*8), chip:chip8, width:64, height:32)
        let keyboardView = UIView(frame:CGRect(x:0, y:32*8, width:64*8, height:64*8))
        view.addSubview(displayView)
        view.addSubview(keyboardView)
        
        let layout = [0x1, 0x2, 0x3, 0xC, 0x4, 0x5, 0x6, 0xD, 0x7, 0x8, 0x9, 0xE, 0xA, 0x0, 0xB, 0xF]
        for i in 0..<16 {
            let button = UIButton(frame: CGRect(x:(layout.index(of:i)!%4)*128, y:(layout.index(of:i)!/4)*128, width:128, height:128))
            button.setTitle(String(format:"%X", i), for:.normal)
            button.addTarget(self, action:#selector(pressButton), for:.touchDown)
            button.addTarget(self, action:#selector(releaseButton), for:.touchUpInside)
            button.addTarget(self, action:#selector(releaseButton), for:.touchUpOutside)
            button.setTitleColor(.white, for:.normal)
            button.showsTouchWhenHighlighted = true
            button.backgroundColor = .orange
            keyboardView.addSubview(button)
        }
        
        self.view = view

    }
    
    override public func viewWillDisappear(_ animated:Bool) {
        self.timer.invalidate()
    }
    
    @objc func pressButton(sender:UIButton) {
        self.chip8.keyboard[Int(sender.title(for:.normal)!, radix:16)!] = true
    }
    
    @objc func releaseButton(sender:UIButton) {
        self.chip8.keyboard[Int(sender.title(for:.normal)!, radix:16)!] = false
    }

    @objc func runCycle() {
        chip8.emulateCycle()
        displayView.refresh()
    }
}
