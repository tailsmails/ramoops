module main

#include "helper.c"

fn C.read_and_time(ptr &u8) u64
fn C.flush_cache_c(ptr &u8)

const page_size = 4096
const num_iterations = 200

fn shuffle_indices(seed u32) ([]int, u32) {
	mut s := seed
	mut arr := []int{len: 256, init: it}
	for i := 255; i > 0; i-- {
		s ^= s << 13
		s ^= s >> 17
		s ^= s << 5
		j := int(s % u32(i + 1))
		temp := arr[i]
		arr[i] = arr[j]
		arr[j] = temp
	}
	return arr, s
}

fn main() {
	size := 256 * page_size
	mut buffer := []u8{len: size, init: 0}
	secret_byte := u8(85)
	mut seed := u32(123456789)

	println('Real Secret Byte: ${secret_byte}')
	println('Calibrating threshold dynamically...')

	unsafe {
		for i in 0 .. 256 {
			buffer[i * page_size] = u8(i)
		}

		test_addr := &buffer[0]
		mut dram_sum := u64(0)
		mut cache_sum := u64(0)
		mut valid_dram_rounds := 0
		mut valid_cache_rounds := 0
		calibration_rounds := 150

		for _ in 0 .. calibration_rounds {
			C.flush_cache_c(test_addr)
			t_dram := C.read_and_time(test_addr)
			if t_dram < 1000 {
				dram_sum += t_dram
				valid_dram_rounds++
			}

			t_cache := C.read_and_time(test_addr)
			if t_cache < 1000 {
				cache_sum += t_cache
				valid_cache_rounds++
			}
		}

		if valid_dram_rounds == 0 || valid_cache_rounds == 0 {
			println('Error during calibration. Too much noise.')
			return
		}

		avg_dram := dram_sum / u64(valid_dram_rounds)
		avg_cache := cache_sum / u64(valid_cache_rounds)
		threshold := (avg_dram + avg_cache) / 2

		println('Calibration -> Avg DRAM: ${avg_dram} ticks, Avg Cache: ${avg_cache} ticks')
		println('Calculated Decision Threshold: ${threshold} ticks')

		if avg_dram <= avg_cache {
			println('WARNING: DRAM and Cache latencies are too close.')
			return
		}

		mut hit_counts := []int{len: 256, init: 0}

		for _ in 0 .. num_iterations {
			for i in 0 .. 256 {
				C.flush_cache_c(&buffer[i * page_size])
			}

			C.read_and_time(&buffer[secret_byte * page_size])
			shuffled_indices, new_seed := shuffle_indices(seed)
			seed = new_seed

			for i in 0 .. 256 {
				mix_i := shuffled_indices[i]
				addr := &buffer[mix_i * page_size]

				for _ in 0 .. 50 {}

				access_time := C.read_and_time(addr)

				if access_time <= threshold {
					hit_counts[mix_i]++
				}
			}
		}

		println('\n--- Statistical Results (Prefetcher-Bypassed) ---')
		mut max_hits := -1
		mut detected_byte := -1

		for i in 0 .. 256 {
			if hit_counts[i] > max_hits {
				max_hits = hit_counts[i]
				detected_byte = i
			}
			if hit_counts[i] > (num_iterations * 15 / 100) {
				println('Byte ${i:3}: Cache Hit registered ${hit_counts[i]:3} times')
			}
		}

		println('------------------------------------------------------')
		println('Final Detected Byte (Highest Hit Count): ${detected_byte} (with ${max_hits} hits)')

		if detected_byte == int(secret_byte) {
			println('SUCCESS: Verification completed successfully!')
		} else {
			println('FAILED: Noise level too high. Try letting the device rest.')
		}
	}
}