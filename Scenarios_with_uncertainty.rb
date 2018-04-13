require 'csv'
price_data = './Prepared_data/*16.csv'
powers_csv = './Prepared_data/process.csv'

# Specify the times of the simulation start
hours = [16]
minutes = [0]
# Specify the lengths of the planning horizons (in 15 minute periods)
horizon_lengths = [16]
# Specify the utilization
utilization = 0.75

# Run the simulation for all specified simulation starts
hours.each do |hour|
  minutes.each do |minute|
    # Specify the reference date (period 1 of the timeline)
    reference_date = Time.utc(2016, 1, 1, hour, minute, 0)
    timeline_min = 1
    # Compute the last period of the timeline
    timeline_max = (Time.utc(2016, 1, 4, 20, 15, 0) -
        reference_date) / (60 * 15) + timeline_min
    timeline_max = ((timeline_max - timeline_min + 1) /
        horizon_lengths.max).floor * horizon_lengths.max

    # IMPORT DATA
    # Declare Hashes for Price Data
    deliveries = {}
    prices = {}
    closing_prices = {}
    # Import price data from CSV file
    # The Price Data requires the form ("DELIBERY", "TRADING_PERIOD", "PRICE_EUR", "CLOSING_PRICE")
    (Dir.glob(price_data).sort!).each do |prices_csv|
      CSV.foreach(prices_csv, headers: true,
                  col_sep: ';') do |row|
        # Import the delivery time
        # Convert it to the corresponding period
        delivery_date = row[0]
        delivery_day = delivery_date.split('.')[0].to_i
        delivery_month = delivery_date.split('.')[1].to_i
        delivery_year = delivery_date.split('.')[2].to_i
        delivery_hour = delivery_date.split(' ')[1].split(':')[0].to_i
        delivery_minute = delivery_date.split(':')[1].to_i
        delivery = Time.utc(delivery_year, delivery_month,
                            delivery_day, delivery_hour, delivery_minute, 0)
        delivery = (delivery - reference_date).to_i /
            (60 * 15) +timeline_min
        # Import the trading time
        # Convert it to the corresponding period
        trading_date = row[1]
        trading_day = trading_date.split('.')[0].to_i
        trading_month = trading_date.split('.')[1].to_i
        trading_year = trading_date.split('.')[2].to_i
        trading_hour = trading_date.split(' ')[1].split(':')[0].to_i
        trading_minute = trading_date.split(':')[1].to_i
        trading_time = Time.utc(trading_year, trading_month, trading_day,
                                trading_hour, trading_minute, 0)
        trading = (trading_time - reference_date).to_i /
            (60 * 15) + timeline_min
        # Import the price assigned to the trading time and the delivery time
        price = row[2].to_f
        # Import the closing price of this delivery time
        closing_price = row[3].to_f


        # Declare new arrays for delivery times and prices
          # if the trading time occurs for the first time
        if deliveries[trading].nil?
          deliveries[trading] = []
          prices[trading] = []
          closing_prices[trading] = []
        end
        # Push the delivery time, the price and the closing price into the array
        deliveries[trading] << delivery
        prices[trading] << price
        closing_prices[trading] << closing_price
      end
    end

    # Import process data from CSV file
    # Declare an array for the process data
    # Process Data requires the form ("PERIOD (15 min)", "MWh")
    process_data = []
    # Push the data into this array
    CSV.foreach(powers_csv, headers: true,
                col_sep: ';') do |row|
      process_data << row[1].to_f
    end

    # SIMULATION
    # Declare Hashes for solution values
    total_costs_spot = {}
    total_costs_forward = {}

    # Simulate planning for all lengths of the planning horizons
    horizon_lengths.each do |horizon_length|
      # Determine the target output of every horizon
      target_output = utilization * horizon_length / 3
      number_horizons = timeline_max / horizon_length
      # Initialize solution values
      total_costs_spot[horizon_length] = 0
      total_costs_forward[horizon_length] = 0


      # Conduct planning in every planning horizon
      0.upto(number_horizons - 1) do |i|
        # Set the start and the end of the planning horizon
        horizon_start = timeline_min + horizon_length * i
        horizon_end = horizon_start + horizon_length - 1
        # Get price data for scheduling
        # Refer to the time of planning
          # (half an hour before the start of the planning horizon)
        process_starts = deliveries[(horizon_start - 2)]
        horizon_prices = prices[(horizon_start - 2)]
        horizon_closing_prices = closing_prices[(horizon_start - 2)]

        # Calculate the planned process costs, the realized process costs,
          # the process utilties and the process ends
        # Declare arrays for the planned process costs,
          # the realized process costs, process utilties and the process ends
        process_costs_spot = []
        process_costs_forward = []
        process_utilities_planned = []
        process_ends = []
        for t in (0..horizon_length - 1) do
          process_costs_spot[t] = 0
          process_costs_forward[t] = 0
          process_utilities_planned[t] = 3000
          # Calculate the processs ends
          process_ends << process_starts[t] +
              process_data.length - 1
          next if process_ends[t] > horizon_end
          # Calculate the planned process costs, the realized process costs,
            # and the process utilties
          process_data.each_with_index do |power, t_process|
            process_costs_spot[t] += power *
                horizon_closing_prices[t + t_process]
            process_costs_forward[t] += power *
                horizon_prices[t + t_process]
            process_utilities_planned[t] -= power *
                horizon_prices[t + t_process]
          end
        end


        # Optimize the schedule (through dynamic programming)
        # Build the matrix with the objective values
        matrix = Array.new(horizon_length + 1) {Array.new(target_output + 1)}
        for n in 0..target_output do
          for t in 0..horizon_length do
            # If no process can start the objective value is zero
            if t == 0 || n == 0
              matrix[t][n] = 0
              # Process can be started
               # if the target output allows to start at least one process
               # and if the process does not exceed the planning horizon
            elsif n >= 1 && process_ends[t - 1] <= horizon_end &&
                process_starts[t - 1] >= horizon_start
              # Calculate the objective value
                # if the process might start
              reference = [process_starts[t - 1] - horizon_start + 1 -
                               process_data.length, 0].max
              pack = process_utilities_planned[t - 1] +
                  matrix[reference][n - 1]

              # Calculate the objective value
                # if the process does not started
              dont_pack = matrix[t - 1][n]
              # Compare objective values
                # if process might be started and if process is not started
              if pack > dont_pack
                # Save greater objective value in the matrix
                matrix[t][n] = pack
              else
                matrix[t][n] = dont_pack
              end
            else
              # Calculate the objective value
              # if the process does not started
              dont_pack = matrix[t - 1][n]
              matrix[t][n] = dont_pack
            end
          end
        end

          for t in 0..horizon_length do
            puts matrix[t].to_s
          end


        # Retrieve the solution from the matrix
        # Calculate the planned and realized costs of the schedule
        n = target_output
        t = horizon_length
        while t > 0 && n > 0
          # Process is started
            # if the objective value in matrix changes
          if matrix[t][n] != matrix[t - 1][n]
            # Add process costs to the total schedule costs
            total_costs_spot[horizon_length] += process_costs_spot[t - 1]
            total_costs_forward[horizon_length] +=
                process_costs_forward[t - 1]
            # Jump to the next sub-problem feasible with the scheduled process
            t = process_starts[t - 1] - process_data.length -
                horizon_start + 1
            n -= 1
            i += 1
          else
            t -= 1
          end
        end
      end
    end


    # Write the solution values to CSV file
    CSV.open('./Planning_Horizons_Sc12.csv', 'a+', col_sep: ';') do |row|
      row << ['Start', 'Planning Horizon Length [h]', 'Costs Scenario 1',
              'Costs Scenario 2']
      total_costs_spot.each do |cycle_length, costs|
        row << ["#{hour}.#{minute}", cycle_length / 4, costs,
                total_costs_forward[cycle_length]]
      end
    end
  end
end
