
--servo PWM channel untuk dropping payload
local K_GRIPPER = 28
local dropping_channel = SRV_Channels:find_channel(K_GRIPPER)

-- Tetapkan target lokasi dropping (sesuaikan dengan lokasi uji)
local target_lat = -7.2768674  -- contoh latitude
local target_lon = 112.7920711-- contoh longitude

-- Konversi ke format integer (derajat * 1e7)
local target_lat_int = math.floor(target_lat * 1e7)
local target_lon_int = math.floor(target_lon * 1e7)
local GPS_ACCURACY = 2  
-- Buat objek lokasi target.
-- Jika sudah ada data home, gunakan sebagai template.
local target = ahrs:get_home()
if target then
    target:lat(target_lat_int)
    target:lng(target_lon_int)
else
    target = Location()
    target:lat(target_lat_int)
    target:lng(target_lon_int)
end

local payload_released = false  -- flag agar payload hanya dilepaskan satu kali

-- Fungsi reset_servo: mengatur servo ke posisi awal (PWM 1200)
function reset_servo()
    SRV_Channels:set_output_pwm_chan_timeout(dropping_channel, 1200, 100)
    gcs:send_text(6, "Servo reset to initial position (PWM 1200)")
    payload_released = false  -- reset flag untuk pengujian berikutnya
    return check_target_location, 1000
end

function check_target_location()
    local pos = {x = 0, y = 0, z = 0}  
    -- Ambil data posisi altitude
    local rel = ahrs:get_relative_position_NED_home()
    local alt = 0 
    if rel then
        alt = -rel:z()  -- Karena nilai z di NED negatif, -z menghasilkan ketinggian dalam meter
    else
        -- fallback: jika data relative tidak tersedia, gunakan nilai dari pos:alt() (asumsi dalam cm)
        alt = (pos:alt() or 0) / 100
    end

     --perhitungan waktu jatuh bebas
     local time= math.sqrt(2*alt/9.8) or 0

     --ambil data kecepatan horizontal (ground speed)
    local GS= ahrs: groundspeed_vector()
    local gs = 0
    if GS then
        gs = math.sqrt(GS:x()^2 + GS:y()^2)
      end

    -- Kecepatan angin
    local angin=ahrs:airspeed_estimate() --ambil data dari air speed sensor

    -- Ambil data posisi saat ini
    local pos = ahrs:get_position()
    if not pos then
        gcs:send_text(0, "GPS data not available")
        return check_target_location, 1000  -- coba lagi dalam 1 detik
    end
    -- Hitung jarak horizontal dari posisi saat ini ke target
    local dist = pos:get_distance(target)
    --Hitung jarak dropping dari target
    local drop=(gs-angin)*time*0.9
    local dropping=drop+GPS_ACCURACY
    gcs:send_text(6, string.format("Target Waypoint: %.1f m, ALT: %.1fm, DROP: %.1f m,Air Speed: %.1f m", dist,alt,dropping,angin))
    
    -- Jika jarak ≤ threshold atau jarak<=perhitungan dropping dan payload belum dilepaskan
    if dist <=GPS_ACCURACY+drop and not payload_released then
        -- Gerakkan servo untuk melepaskan payload (PWM 1900 selama 100ms)
        SRV_Channels:set_output_pwm_chan_timeout(dropping_channel, 1900, 100)
        gcs:send_text(6, "Target reached, payload dropped!")
        payload_released = true
        -- Setelah payload dilepaskan, tunggu 10 detik, kemudian reset servo
        return reset_servo, 20000
    end
    
    return check_target_location, 1000  -- periksa setiap 1 detik
end

return check_target_location()
