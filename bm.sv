module noc (nocif n, crc_if c);

logic [2:0] CurrentState;
logic [2:0] NextState;
logic [7:0] SourceID, OtherSourceID, PreviousSourceID, Framing;
typedef enum logic [5:0] {state1, state2, state3, state4, state5, state6} STATE1;
typedef enum logic [9:0] {sstate1, sstate2, sstate3, sstate4, sstate5, sstate6, sstate7, sstate8, sstate9, sstate10} STATE2;
typedef enum logic [15:0] {ssstate1, ssstate2, ssstate3, ssstate4, ssstate5, ssstate6, ssstate7, ssstate8, ssstate9, ssstate10, ssstate11, ssstate12, ssstate13, ssstate14, ssstate15, ssstate16} STATE3;
typedef enum logic [2:0] {sssstate1, sssstate2, sssstate3} STATE4;
typedef enum logic [2:0] {ssssstate1, ssssstate2, ssssstate3} STATE5;
typedef enum logic [1:0] {sssssstate1, sssssstate2} STATE6;
typedef enum logic [20:0] {BusBegin1, BusBegin2, BusBegin3, BusBegin4, BusBegin5, BusBegin6, BusBegin7, BusBegin8, BusBegin9, BusBegin10, BusBegin11, BusBegin12, BusBegin13, BusBegin14, BusBegin15, BusBegin16, BusBegin17, BusBegin18, BusBegin19, BusBegin20, BusBegin21} STATE7;

STATE1 STATE_READ;
STATE2 STATE_WRITE;
STATE3 STATE_READ_RESP;
STATE4 ForStorageData3;
STATE5 STATE_WRITE_RESP;
STATE6 ForStorageData2;
STATE7 BusMaster;

logic [7:0] StartBus, SourceIDBus, TwoOptions, BusAddress1, BusAddress2, BusAddress3, BusAddress4, BusData1, BusData2, BusData3, BusData4; 
logic [32:0] TotalBusData;
logic [7:0] Addr1_rd, Addr2_rd, Addr3_rd, Addr4_rd; // to store into addr
logic [7:0] Addr1_wr, Addr2_wr, Addr3_wr, Addr4_wr; // to store into addr
logic [7:0] Data1, Data2, Data3, Data4; // to store into data_wr
logic [7:0] test, test1; 
logic passBus;
logic wr_en, rd_en, full, empty, pass, ReadResp, passing; //GoReadResp, 
logic wr_en1, rd_en1, full1, empto, WriteResp;
logic AccessStateFor0C, EnableStateFor0C, EnableStateFor08, AccessStateFor08, Access04Resp;
logic [7:0] StorageFraming, StorageReturnID, StorageExtension; 
logic [31:0] StorageData1, StorageData2, StorageData3;
logic [119:0] FullStorageRead, FullStorageFIFORead, SaveIt; // (framing, sourceID, AllData, Extention), (40, ReturnID)
logic [15:0] FullStorageWrite, FullStorageFIFOWrite; // (80) , (ReturnID)

parameter IDLE = 3'b000; // it fills the bus, if data comes in, it ignores it
parameter READ = 3'b001;
parameter READ_RESP = 3'b010;
parameter WRITE = 3'b011;
parameter WRITE_RESP = 3'b100;
parameter RESERVED = 3'b101;
parameter MESSAGE = 3'b110;
parameter END = 3'b111;
logic SASSOUN;

fifoRead SAS (.wr_en(wr_en), .rst(n.rst), .full(full), .empty(empty), .clk(n.clk), .rd_en(rd_en), .FullStorageRead(FullStorageRead), .FullStorageFIFORead(FullStorageFIFORead));

always @ (posedge n.clk or posedge n.rst) 
begin

		if (n.rst == 1'b1) //goes through one time in the beginning
			begin	
				CurrentState = IDLE;
				STATE_READ = state1;
				STATE_WRITE = sstate1;
				STATE_READ_RESP = ssstate1;
				ForStorageData3 = sssstate1;
				STATE_WRITE_RESP = ssssstate1;
				BusMaster = BusBegin1;
				passBus = 1'b0;
				SASSOUN =1'b1;
				c.Sel = 0;
				c.RW = 0;
				n.CmdR = 1;
				passing = 1'b0;
				n.DataR = 8'b00000000;
				rd_en = 1'b0;
				rd_en1 = 1'b0;
				wr_en = 1'b0;
				wr_en1 = 1'b0;
				for(int count=0; count<120; count++)  // clear all data from the memory initially
					begin
						FullStorageRead[count] = 0;
						SaveIt[count] = 0;
					end 

				for(int count=0; count<16; count++)  // clear all data from the memory initially
					begin
						FullStorageWrite[count] = 0;
					end 
			end

else if (n.rst != 1'b1)
begin

case(CurrentState) // making sure everything loops in this case until it ends

	IDLE:  // IDLE determines what next state will be (read, readresponse, write...)
	begin
		c.RW =0;
		n.CmdR = 1;
		n.DataR = 8'b00000000;
		
		if (Access04Resp)
		begin
		wr_en = 1'b0;
		rd_en = 1'b1;
		Access04Resp = 1'b0;
		ReadResp = 1'b1;
		c.Sel = 0; // write the chain into fifo
		c.RW = 0;	
		end

		if (EnableStateFor0C == 1'b0)
		begin
			c.Sel = 0;
		end

		if (EnableStateFor0C == 1'b1)
		begin
			AccessStateFor0C = 1'b1; // get StorageData3
		end

		if (EnableStateFor08)
		begin
			AccessStateFor08 = 1'b1; // get StorageData3
		end

		if ((n.CmdW == 1'b1) && (n.DataW[7:5] == 3'b001)) // when CmdR=1 and code=001 (checking the framing), READ state is enabled
			begin 
				CurrentState = READ;
				StorageFraming = n.DataW;
				passing = 1'b0;  
			end

		else if ((n.CmdW == 1'b1) && (n.DataW[7:5] == 3'b011)) // when CmdR=1 and code=011, WRITE state is enabled
			begin 
				CurrentState = WRITE;
				Framing = n.DataW; 
			end

		else if ((n.CmdW == 1'b1) && (n.DataW[7:5] == 3'b100)) // when CmdR=1 and code=011, WRITE state is enabled
			begin 
				CurrentState = WRITE_RESP; 
			end
	end


	READ:
	begin

		if ((n.CmdW == 1'b0) && (SASSOUN == 1'b1))  // after READ happens (CmdW=1), the first CmdW=0 will be your SourceID
			begin	
				SourceID [7:0] = {n.DataW};
				SASSOUN =1'b0;
				c.RW =0;
				c.Sel =0;
				//n.CmdR = 0;
			end

		case(STATE_READ) 
		
				state1:
					begin
						STATE_READ = state2; // skip the SourceID
					end

				state2:   			// 1 byte (8 bits)		// READ state
					begin
						Addr1_rd =n.DataW;
						c.RW =0;
						c.Sel =0;
						StorageReturnID = SourceID;
						wr_en = 1'b0;
						STATE_READ =state3;
					end

				state3:                         // 2 bytes (16 bits)
					begin
						Addr2_rd =n.DataW;
						c.RW =0;
						c.Sel =0;
						STATE_READ =state4; 
					end

				state4:                         // 3 bytes (24 bits)
					begin
						Addr3_rd =n.DataW;
						c.RW =0;
						c.Sel =0;
						STATE_READ =state5;
					end

				state5:                         // 4 bytes (32 bits)
					begin
						Addr4_rd =n.DataW;
				c.addr [31:0] ={Addr4_rd, Addr3_rd, Addr2_rd, Addr1_rd}; // all 4 bytes of data will be stored into input of CRC
						c.RW =0;
						c.Sel =1;
						STATE_READ =state6;
					end

				state6:
					begin	

						if (n.DataW == 8'b0000_1100) // 0C (we need to increment 2 times)
							begin
								c.addr = (c.addr + 8'b0000_0100); // increment by 4
								c.Sel =1; // everytime we have a new address, make Sel=1
								EnableStateFor0C = 1'b1; // to make the state7 to run independantly parallel
								StorageData1 [31:0]= c.data_rd [31:0]; 
								StorageExtension = n.DataW; 
							end

						else if (n.DataW == 8'b0000_1000) // 08 (increment 1 time)
							begin
								c.addr = (c.addr + 8'b0000_0100); // increment by 4
								c.Sel =1; // everytime we have a new address, make Sel=1
								StorageData1 [31:0]= c.data_rd [31:0]; 
								StorageData3 [31:0]= 32'h0000_0000;  
								StorageExtension = n.DataW; 
								EnableStateFor08 = 1'b1;
							end

						else if (n.DataW == 8'b0000_0100) // 04 (dont increment)
							begin
								c.Sel = 0; // everytime we have a new address, make Sel=1
								StorageData1 [31:0]= c.data_rd [31:0]; 
								StorageData2 [31:0] = 32'h0000_0000;
								StorageData3 [31:0] = 32'h0000_0000;
								StorageExtension = n.DataW;
		FullStorageRead [119:0] = {StorageFraming, StorageReturnID, StorageData1, StorageData2, StorageData3, StorageExtension}; 
								wr_en = 1'b1;
								rd_en = 1'b0;
								Access04Resp = 1'b1;
							end	
					
						c.RW =0;					
						SASSOUN = 1'b1;
						pass = 1'b1;
						STATE_READ = state1;
						CurrentState = IDLE; // the next cycle will be framing (for IDLE)
					end
		endcase
	end


	WRITE:
	begin

		if ((n.CmdW == 1'b0) && (SASSOUN == 1'b1))  // after READ happens (CmdW=1), the first CmdW=0 will be your SourceID
			begin
				SourceID [7:0] = {n.DataW};
				SASSOUN =1'b0;
				c.RW =0;
				c.Sel =0;
				//n.CmdR = 0;	
			end

		case(STATE_WRITE) 
				sstate1:
					begin
						STATE_WRITE = sstate2; // skip the SourceID
					end

				sstate2:   			// 1 byte (8 bits) for addr
					begin
						Addr1_wr =n.DataW;
						c.RW =0;
						c.Sel =0;
						STATE_WRITE = sstate3;
					end

				sstate3:                         // 2 bytes (16 bits)
					begin
						Addr2_wr =n.DataW;
						c.RW =0;
						c.Sel =0;
						STATE_WRITE =sstate4; 
					end

				sstate4:                         // 3 bytes (24 bits)
					begin
						Addr3_wr =n.DataW;
						c.RW =0;
						c.Sel =0;
						STATE_WRITE =sstate5;
					end

				sstate5:                         // 4 bytes (32 bits)
					begin
						Addr4_wr =n.DataW;
						c.RW =0;
						c.Sel =0;
						STATE_WRITE = sstate6;
					end

				sstate6: 
					begin
						c.RW =0;
						c.Sel =0;
						if(passing == 1'b1)
						begin
							StorageReturnID = PreviousSourceID [7:0];
							StorageFraming [7:0] = Framing;
					FullStorageRead [119:0] = {StorageFraming, StorageReturnID, 32'h0000, 32'h0000, 32'h0000, 8'b0000_0000};
							wr_en = 1'b1;
						end
						STATE_WRITE = sstate7; // we will assume DataW = 04 (do not increment)
					end

				sstate7:  			// 1 byte (8 bits) for Data	
					begin
						PreviousSourceID [7:0] = SourceID[7:0];
						wr_en = 1'b0;
						if(passing == 1'b1) 
						begin 
							rd_en = 1'b1;
							WriteResp = 1'b1;
							passing = 1'b0;
						end
						Data1 =n.DataW;
						c.RW =0;
						c.Sel =0;
						STATE_WRITE = sstate8;
					end

				sstate8:                         // 2 bytes (16 bits)
					begin
						Data2 =n.DataW;
						c.RW =0;
						c.Sel =0;
						rd_en = 1'b0;
						STATE_WRITE = sstate9; 
					end

				sstate9:                         // 3 bytes (24 bits)
					begin
						Data3 =n.DataW;
						c.RW =0;
						c.Sel =0;
						STATE_WRITE =sstate10;
					end

				sstate10:                         // 4 bytes (32 bits) for Data
					begin
						Data4 =n.DataW;
						c.data_wr [31:0] ={Data4, Data3, Data2, Data1};// all 4 bytes of data will be stored into input of CRC
						c.addr [31:0] ={Addr4_wr, Addr3_wr, Addr2_wr, Addr1_wr}; // all 4 bytes of data will be stored into input of CRC
						c.RW =1;
						c.Sel =1;
						SASSOUN = 1'b1;
						passing = 1'b1;
						CurrentState = IDLE;
						STATE_WRITE = sstate1;
						
					end
		endcase
end
endcase
end
end

always @ (posedge n.clk) 
begin
	if (AccessStateFor0C == 1'b1)
	begin
	case(ForStorageData3)
	sssstate1:
		begin	
			c.addr =(c.addr + 8'b0000_0100); // increment by 8
			c.Sel = 1;
			c.RW = 0;
			StorageData2 [31:0] = c.data_rd [31:0];
			ForStorageData3 = sssstate2; 	
		end

	sssstate2:
		begin
			StorageData3 [31:0] = c.data_rd [31:0]; //store the last data in the chain	
			c.Sel = 0;
			c.RW = 0;
FullStorageRead [119:0] = {StorageFraming, StorageReturnID, StorageData1, StorageData2, StorageData3, StorageExtension};
			wr_en = 1'b1;
			ForStorageData3 = sssstate3;
		end

	sssstate3:
		begin
			c.Sel = 0; // write the chain into fifo
			c.RW = 0;
			rd_en = 1'b1; // read from fifo for the next cycle (ssstate2)
			ReadResp = 1'b1; 
			wr_en = 1'b0;
			AccessStateFor0C = 1'b0;	
			EnableStateFor0C = 1'b0;
			ForStorageData3 = sssstate1;
		end
	endcase
	end

	if (AccessStateFor08 == 1'b1)
	begin
	case(ForStorageData2)
	sssssstate1:
		begin
			c.Sel = 0;
			c.RW = 0;
			StorageData2 [31:0] = c.data_rd [31:0]; // get the data2	
			rd_en = 1'b0;
			FullStorageRead [119:0] = {StorageFraming, StorageReturnID, StorageData1, StorageData2, StorageData3, StorageExtension};
			wr_en = 1'b1;
			ForStorageData2 = sssssstate2;
		end

	sssssstate2:
		begin
			c.Sel = 0;
			c.RW = 0;
			AccessStateFor08 = 1'b0;
			EnableStateFor08 = 1'b0;
			wr_en = 1'b0;
			rd_en = 1'b1;
			ReadResp = 1'b1;
			ForStorageData2 = sssssstate1;
		end
		endcase
	end		

	if (ReadResp == 1'b1)
	begin
		case(STATE_READ_RESP)
		ssstate1:
		begin
			n.DataR = 8'b0100_0000; // framing (40)
			STATE_READ_RESP = ssstate2;
		end

		ssstate2:
		begin
			n.CmdR = 0;
			SaveIt[119:0] = FullStorageFIFORead[119:0]; // we must wait one cycle to store everything from fifo into register
			n.DataR = SaveIt[111:104]; // Return ID
			STATE_READ_RESP = ssstate3;
			rd_en = 1'b0;
		end

		ssstate3:
		begin
			n.CmdR = 0;
			n.DataR = SaveIt[103:96]; // Data1, part1
			STATE_READ_RESP = ssstate4;
		end

		ssstate4:
		begin
			n.CmdR = 0;
			n.DataR = SaveIt[95:88]; // Data1, part2
			STATE_READ_RESP = ssstate5;
		end

		ssstate5:
		begin
			n.CmdR = 0;
			n.DataR = SaveIt[87:80]; // Data1, part3
			STATE_READ_RESP = ssstate6;
		end

		ssstate6:
		begin
			n.CmdR = 0;
			n.DataR = SaveIt[79:72]; // Data1, part4
			STATE_READ_RESP = ssstate7;
		end

		ssstate7:
		begin
			if (FullStorageFIFORead[7:0] == 8'b0000_1100 || FullStorageFIFORead[7:0] == 8'b0000_1000) //0C or 08
			begin
				n.CmdR = 0;
				n.DataR = SaveIt[71:64]; // Data2, part1
			end

			else if (FullStorageFIFORead[7:0] == 8'b0000_0100) //04 finish it
			begin
				n.CmdR = 1;
				n.DataR = 8'b1111_1111;  // end code
			end
			STATE_READ_RESP = ssstate8;
		end

		ssstate8:
		begin
			if (FullStorageFIFORead[7:0] == 8'b0000_1100 || FullStorageFIFORead[7:0] == 8'b0000_1000) //0C or 08
			begin
				n.CmdR = 0;
				n.DataR = SaveIt[63:56]; // Data2, part2
			end

			else if (FullStorageFIFORead[7:0] == 8'b0000_0100) //04 finish it
			begin
				n.DataR = 8'b0000_0000;
			end
			STATE_READ_RESP = ssstate9;
		end

		ssstate9:
		begin
			if (FullStorageFIFORead[7:0] == 8'b0000_1100 || FullStorageFIFORead[7:0] == 8'b0000_1000) //0C or 08
			begin
				n.CmdR = 0;
				n.DataR = SaveIt[55:48]; // Data2, part3
			end

			else if (FullStorageFIFORead[7:0] == 8'b0000_0100) //04 finish it
			begin
				n.DataR = 8'b0000_0000;
			end
			STATE_READ_RESP = ssstate10;
		end

		ssstate10:
		begin
			if (FullStorageFIFORead[7:0] == 8'b0000_1100 || FullStorageFIFORead[7:0] == 8'b0000_1000) //0C or 08
			begin
				n.CmdR = 0;
				n.DataR = SaveIt[47:40]; // Data2, part4
			end

			else if (FullStorageFIFORead[7:0] == 8'b0000_0100) //04 finish it
			begin
				n.DataR = 8'b0000_0000;
			end
			STATE_READ_RESP = ssstate11;
		end

		ssstate11:
		begin
			if (FullStorageFIFORead[7:0] == 8'b0000_1100) //0C
			begin
				n.CmdR = 0;
				n.DataR = SaveIt[39:32]; // Data3, part1
			end

			else if (FullStorageFIFORead[7:0] == 8'b0000_0100) //04
			begin
				n.DataR = 8'b0000_0000;
			end

			else if (FullStorageFIFORead[7:0] == 8'b0000_1000) //08
			begin
				n.CmdR = 1;
				n.DataR = 8'b1111_1111;
			end
			
			STATE_READ_RESP = ssstate12;
		end

		ssstate12:
		begin
			if (FullStorageFIFORead[7:0] == 8'b0000_1100) //0C
			begin
				n.CmdR = 0;
				n.DataR = SaveIt[31:24]; // Data3, part2
			end

			else if (FullStorageFIFORead[7:0] == 8'b0000_0100 || FullStorageFIFORead[7:0] == 8'b0000_1000) //04 or 08 finish it
			begin
				n.DataR = 8'b0000_0000;
			end
			STATE_READ_RESP = ssstate13;
		end

		ssstate13:
		begin
			if (FullStorageFIFORead[7:0] == 8'b0000_1100) //0C
			begin
				n.CmdR = 0;
				n.DataR = SaveIt[23:16]; // Data3, part3
			end

			else if (FullStorageFIFORead[7:0] == 8'b0000_0100 || FullStorageFIFORead[7:0] == 8'b0000_1000) //04 or 08 finish it
			begin
				n.DataR = 8'b0000_0000;
			end
			STATE_READ_RESP = ssstate14;
		end

		ssstate14:
		begin
			if (FullStorageFIFORead[7:0] == 8'b0000_1100) //0C
			begin
				n.CmdR = 0;
				n.DataR = SaveIt[15:8]; // Data3, part4
			end

			else if (FullStorageFIFORead[7:0] == 8'b0000_0100 || FullStorageFIFORead[7:0] == 8'b0000_1000) //04 or 08 finish it
			begin
				n.DataR = 8'b0000_0000;
			end
			STATE_READ_RESP = ssstate15;
		end

		ssstate15:
		begin
			if (FullStorageFIFORead[7:0] == 8'b0000_1100) //0C
			begin
				n.CmdR = 1;
				n.DataR = 8'b1111_1111;  // End code
			end

			else if (FullStorageFIFORead[7:0] == 8'b0000_0100 || FullStorageFIFORead[7:0] == 8'b0000_1000) //04 or 08 finish it
			begin
				n.DataR = 8'b0000_0000;
			end
			STATE_READ_RESP = ssstate16;
		end

		ssstate16:
		begin
			n.CmdR = 1;
			n.DataR = 8'b0000_0000;  // Reset them before you finish
			ReadResp = 1'b0;
			c.RW =0;
			STATE_READ_RESP = ssstate1;
		end
		endcase
	end

	if (WriteResp == 1'b1)
	begin
		case(STATE_WRITE_RESP)
		ssssstate1:
		begin
			n.DataR = 8'b1000_0000; // framing (80)
			STATE_WRITE_RESP = ssssstate2;
		end

		ssssstate2:
		begin
			n.CmdR = 0;
			n.DataR = FullStorageFIFORead[111:104];
			rd_en = 1'b0;
			STATE_WRITE_RESP = ssssstate3;
		end

		ssssstate3:
		begin
			n.CmdR = 1;
		        c.RW =0;
			n.DataR = 8'b0000_0000;  // Reset them before you finish
			WriteResp = 1'b0;
			STATE_WRITE_RESP = ssssstate1;
		end
		endcase
	end
end


always @ (posedge n.clk) // Bus Master!!!!!!!!
begin			
		case(BusMaster)

			BusBegin1:
			begin
				if (n.CmdR == 1'b1 && n.DataW == 8'b0110_1000) // 68
				begin
				StartBus [7:0] = n.DataW;
				BusMaster = BusBegin2;
				end
			end

			BusBegin2:
			begin
				SourceIDBus [7:0] = n.DataW;
				BusMaster = BusBegin3;
			end

			BusBegin3:
			begin
				TwoOptions [7:0] = n.DataW; // F0 vs F4
				BusMaster = BusBegin4;
			end

			BusBegin4:
			begin
				BusMaster = BusBegin5; // skip 04
			end

			BusBegin5:
			begin
				if(TwoOptions == 8'b1111_0000)
				begin
				BusMaster = BusBegin6; // go to F0
				end

				else if(TwoOptions == 8'b1111_0100)
				begin
				BusMaster = BusBegin11; // go to F4
				end

				else begin passBus=1'b1; 
					   BusMaster = BusBegin21; end
			end

			BusBegin6:
			begin
					BusAddress1 = n.DataW; 
					BusMaster = BusBegin8;
			end

			BusBegin7:
			begin
				BusAddress2 = n.DataW; 
				BusMaster = BusBegin9;
			end

			BusBegin8:
			begin
				BusAddress3 = n.DataW; 
				BusMaster = BusBegin10;
			end

			BusBegin9:
			begin
				BusAddress4 = n.DataW; 
				BusMaster = BusBegin10; // go back after storing the register
			end

			BusBegin10:
			begin
				BusMaster = BusBegin1; // do nothing and go back 00
			end

			BusBegin11:
			begin
				BusData1 = n.DataW;
				BusMaster = BusBegin12;
			end

			BusBegin12:
			begin
				BusData2 = n.DataW;
				BusMaster = BusBegin13;
			end

			BusBegin13:
			begin
				BusData3 = n.DataW;
				BusMaster = BusBegin14;
			end

			BusBegin14:
			begin
				BusData4 = n.DataW;
				TotalBusData [32:0] = {BusData1, BusData2, BusData3, BusData4};
				BusMaster = BusBegin15;
			end

			BusBegin15:
			begin
				if (TotalBusData[32:0] == 32'h0000_0000)
				begin
					BusMaster = BusBegin1;
				end
			
				else if (TotalBusData[32:0] != 32'h0000_0000)
				begin
					//n.CmdR = 1'b1;
					n.DataR = 8'b0010_0011; //23
					BusMaster = BusBegin16;
				end
			end

			BusBegin16:
			begin
					n.DataR = 8'b0001_0001; // Any sourceID
					BusMaster = BusBegin17;
			end

			BusBegin17:
			begin
					n.DataR = BusAddress1;
					BusMaster = BusBegin18;
			end

			BusBegin18:
			begin
					n.DataR = BusAddress2;
					BusMaster = BusBegin19;
			end

			BusBegin19:
			begin
					n.DataR = BusAddress3;
					BusMaster = BusBegin20;
			end

			BusBegin20:
			begin
					n.DataR = BusAddress4;
					BusMaster = BusBegin21;
			end

			BusBegin21:
			begin
				if(passBus == 1'b1)
				begin
					passBus = 1'b0;
					BusMaster = BusBegin1;
				end
				else 
				begin
					n.DataR = 8'b0010_0000; //20	
				end
				BusMaster = BusBegin1;
			end
		endcase
	end
endmodule

		  
		  
 module fifoRead (wr_en,rst,full,empty,clk,rd_en,FullStorageRead,FullStorageFIFORead);
 parameter width=120;
 parameter depth=20; 

 input wr_en,rd_en,rst,clk;
 output full,empty;
 input [width-1:0] FullStorageRead;
 output reg [width-1:0] FullStorageFIFORead;
 reg  [width-1 :0 ] data_mem [depth-1 : 0 ];
 reg [3 :0 ] wr_ptr,rd_ptr;

 assign full = ((wr_ptr ==20)&&(rd_ptr==0))?1:((rd_ptr == wr_ptr +1)?1:0);
 assign empty = (rd_ptr == wr_ptr)?1:0;

 always @ (posedge clk,posedge rst)
 begin
 if (rst)
 begin
 wr_ptr <= 0;
 rd_ptr <= 0;
 end
 else
 begin
 if (rd_en && !empty)
 begin
 FullStorageFIFORead <= data_mem[rd_ptr];
 rd_ptr <= rd_ptr +1;
 end
 else
 begin
 FullStorageFIFORead <= FullStorageFIFORead;
 rd_ptr <= rd_ptr;
 end
 if (wr_en && !full)
 begin
 data_mem[wr_ptr] <= FullStorageRead;
 wr_ptr <= wr_ptr +1;
 end
 else
 begin
 data_mem[wr_ptr] <= data_mem[wr_ptr];
 wr_ptr <= wr_ptr;
 end
 end
 end
	
 endmodule

