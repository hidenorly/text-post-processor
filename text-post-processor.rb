#!/usr/bin/ruby

# Copyright 2018 hidenorly
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fileutils'
require 'optparse'

class StrUtil
	def self.ensureUtf8(str, replaceChr="_")
		str = str.to_s
		str.encode!("UTF-8", :invalid=>:replace, :undef=>:replace, :replace=>replaceChr) if !str.valid_encoding?
		return str
	end

	def self.convLineArrayToString(buf)
		consolidatedBuf = nil

		buf.each do |aLine|
			consolidatedBuf = "#{consolidatedBuf!=nil ? "#{consolidatedBuf}\n" :  ""}#{aLine}"
		end

		return consolidatedBuf
	end
end

class FileUtil
	def self.ensureDirectory(path)
		paths = path.split("/")

		path = ""
		paths.each do |aPath|
			path += "/"+aPath
			Dir.mkdir(path) if !Dir.exist?(path)
		end
	end

	def self.iteratePath(path, matchKey, pathes, recursive, dirOnly)
		Dir.foreach( path ) do |aPath|
			next if aPath == '.' or aPath == '..'

			fullPath = path.sub(/\/+$/,"") + "/" + aPath
			if FileTest.directory?(fullPath) then
				if dirOnly then
					if matchKey==nil || ( aPath.match(matchKey)!=nil ) then 
						pathes.push( fullPath )
					end
				end
				if recursive then
					iteratePath( fullPath, matchKey, pathes, recursive, dirOnly )
				end
			else
				if !dirOnly then
					if matchKey==nil || ( aPath.match(matchKey)!=nil ) then 
						pathes.push( fullPath )
					end
				end
			end
		end
	end

	# get regexp matched file list
	def self.getRegExpFilteredFiles(basePath, fileFilter)
		result=[]
		iteratePath(basePath, fileFilter, result, true, false)

		return result
	end

	def self.getDirectoryFromPath(path)
		pos = path.rindex("/")
		return pos ? path.slice(0,pos) : path
	end

	def self.readFileAsArray(path, enableStrip=true)
		result = []

		if path && FileTest.exist?(path) then
			fileReader = File.open(path)
			if fileReader then
				while !fileReader.eof
					aLine = StrUtil.ensureUtf8(fileReader.readline)
					aLine.strip! if enableStrip
					aLine.rstrip! if !enableStrip
					result << aLine
				end
				fileReader.close
			end
		end

		return result
	end

	def self.writeFile(path, body)
		if path then
			fileWriter = File.open(path, "w")
			if fileWriter then
				if body.kind_of?(Array) then
					body.each do |aLine|
						fileWriter.puts aLine
					end
				else
					fileWriter.puts body
				end
				fileWriter.close
			end
		end
	end
end

class RuleParser
	DEF_TYPE_COMMENT = 0
	DEF_TYPE_TARGET_FILE = 1
	DEF_TYPE_REPLACE_FROM = 2
	DEF_TYPE_REPLACE_FROM_END = 3
	DEF_TYPE_REPLACE_FROM_REGEXP = 4
	DEF_TYPE_REPLACE_TO = 5
	DEF_TYPE_REPLACE_TO_END = 6

	def self._checkType(aLine, mode)
		if aLine.start_with?("###") && aLine.end_with?("###") && aLine.length>=6 then
			mode = DEF_TYPE_COMMENT
			aLine = aLine[3...aLine.length-4]
		elsif aLine.start_with?("[[[") && aLine.end_with?("]]]") && aLine.length>=6 then
			mode = DEF_TYPE_TARGET_FILE
			aLine = aLine[3...aLine.length-3]
		elsif aLine.start_with?("!!!") && aLine.length>3 && mode!=DEF_TYPE_REPLACE_FROM then
			mode = DEF_TYPE_REPLACE_FROM
			aLine = aLine[3..aLine.length]
			if aLine.end_with?("!!!") then
				aLine = aLine[0..aLine.length-4]
				mode = DEF_TYPE_REPLACE_FROM_END
			end
		elsif aLine.end_with?("!!!") && mode==DEF_TYPE_REPLACE_FROM then
			mode = DEF_TYPE_REPLACE_FROM_END
			aLine = aLine[3..aLine.length]
		elsif aLine.start_with?("$$$") && mode!=DEF_TYPE_REPLACE_TO then
			mode = DEF_TYPE_REPLACE_TO
			aLine = aLine[3..aLine.length]
			if aLine.end_with?("$$$") then
				aLine = aLine[0..aLine.length-4]
				mode = DEF_TYPE_REPLACE_TO_END
			end
		elsif aLine.end_with?("$$$") then
			mode = DEF_TYPE_REPLACE_TO_END
			aLine = aLine[0..aLine.length-4]
		elsif aLine.start_with?("///") && aLine.end_with?("///") && aLine.length>6 then
			mode = DEF_TYPE_REPLACE_FROM_REGEXP
			aLine = Regexp.new(aLine[3..aLine.length-4])
		end

		return aLine, mode
	end

	def self._addNewTarget(result, currentTargetFile, currentTarget)
		if currentTargetFile && (!(currentTarget[:replace_from].kind_of?(Array) && currentTarget[:replace_from].empty?) || currentTarget[:replace_from].kind_of?(Regexp)) && !currentTarget[:replace_to].to_a.empty? then
			result[ currentTargetFile ] = [] if !result.has_key?(currentTargetFile)

			currentTarget[:replace_from] = StrUtil.convLineArrayToString(currentTarget[:replace_from]) if currentTarget[:replace_from].kind_of?(Array) 
			currentTarget[:replace_to] = StrUtil.convLineArrayToString(currentTarget[:replace_to]) if currentTarget[:replace_to].kind_of?(Array) 

			result[ currentTargetFile ] << currentTarget
		end
		return {:replace_from=>[], :replace_to=>[]}
	end

	def self.loadRule(path)
		result = {}

		buf = FileUtil.readFileAsArray(path, false)

		mode = DEF_TYPE_COMMENT
		currentTargetFile = nil
		currentTarget = _addNewTarget(result, currentTargetFile, currentTarget)

		buf.each do |aLine|
			oldMode = mode
			aLine, mode = _checkType(aLine, mode)
			case mode
			when DEF_TYPE_COMMENT,DEF_TYPE_TARGET_FILE then
				currentTarget = _addNewTarget(result, currentTargetFile, currentTarget)
				currentTargetFile = aLine
			when DEF_TYPE_REPLACE_FROM,DEF_TYPE_REPLACE_FROM_END then
				if oldMode!=DEF_TYPE_REPLACE_FROM then
					currentTarget = _addNewTarget(result, currentTargetFile, currentTarget)
				end
				currentTarget[:replace_from] << aLine if !aLine.empty?
			when DEF_TYPE_REPLACE_TO,DEF_TYPE_REPLACE_TO_END then
				currentTarget[:replace_to] << aLine if !aLine.empty?
				if mode==DEF_TYPE_REPLACE_TO_END then
					currentTarget = _addNewTarget(result, currentTargetFile, currentTarget)
				end
			when DEF_TYPE_REPLACE_FROM_REGEXP then
				if oldMode!=DEF_TYPE_REPLACE_FROM_REGEXP then
					currentTarget = _addNewTarget(result, currentTargetFile, currentTarget)
				end
				currentTarget[:replace_from] = aLine
			end
		end

		return result
	end
end


class TextPostProcessor
	def self.execute(inFilePath, outFilePath, rules)
		buf = FileUtil.readFileAsArray(inFilePath)

		convLineArrayToString = StrUtil.convLineArrayToString(buf)

		if convLineArrayToString then
			rules.each do |aFileRule, theRule|
				aFileRule=!aFileRule.to_s.empty? ? Regexp.new(aFileRule) : nil
				if !aFileRule || inFilePath.to_s.match(aFileRule)!=nil then
					theRule.each do |aRule|
						regexpKey = aRule[:replace_from].kind_of?(Regexp) ? aRule[:replace_from] : Regexp.new(Regexp.escape(aRule[:replace_from]))
						convLineArrayToString = convLineArrayToString.gsub( regexpKey, aRule[:replace_to] )
					end
				end
			end
		end

		outFilePath = outFilePath ? outFilePath : inFilePath
		FileUtil.ensureDirectory( FileUtil.getDirectoryFromPath(outFilePath) )
		FileUtil.writeFile(outFilePath, convLineArrayToString)
	end
end

options = {
	:outPath => nil,
	:verbose => false
}

opt_parser = OptionParser.new do |opts|
	opts.banner = "Usage: targetFile rule.cfg"

	opts.on("-o", "--outFile=", "Specify if you want to output as other file") do |outPath|
		options[:outPath] = outPath
	end

	opts.on("-v", "--verbose", "Enable verbose status output (default:#{options[:verbose]})") do
		options[:verbose] = true
	end
end.parse!

if (ARGV.length < 2) then
	puts "Please specify #{File.basename($PROGRAM_NAME)} targetFile ruleFile"
	exit(-1)
end

rules = RuleParser.loadRule(ARGV[1])
puts rules if options[:verbose]

paths = []
if FileTest.directory?(ARGV[0]) then
	FileUtil.iteratePath(ARGV[0], nil, paths, false, false)
else
	paths << ARGV[0]
end

paths.each do |aPath|
	TextPostProcessor.execute(aPath, options[:outPath], rules)
end
