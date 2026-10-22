WHISPER_ELF_PATH  ?= build/readshared.elf
WHISPER_MAX_INSN  ?= 0
WHISPER_VERBOSE   ?= 0
WHISPER_TRACE_OUT ?= whisper_trace2.log
WHISPER_LOG       ?= 0


WHISPER_OPTS := --isa rv64imafdc --xlen 64 -t $(WHISPER_ELF_PATH) --configfile cva6_config.json

ifneq ($(WHISPER_MAX_INSN),0)
    WHISPER_OPTS += --maxinst $(WHISPER_MAX_INSN):f
endif

ifneq ($(WHISPER_VERBOSE), 0)
	WHISPER_OPTS += -v -l
endif

ifneq ($(WHISPER_LOG), 0)
	WHISPER_OPTS += > $(WHISPER_TRACE_OUT)
endif

run_whisper:
	whisper $(WHISPER_OPTS)