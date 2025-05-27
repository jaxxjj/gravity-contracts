#!/bin/bash
# 保存为 find_stack_too_deep.sh

# 获取src目录下所有sol文件
files=$(find src -name "*.sol")

echo "开始检查每个合约文件..."

# 遍历每个文件
for file in $files; do
  echo "编译 $file ..."
  output=$(forge build --contracts $file -vvv 2>&1)
  
  # 检查是否有stack too deep错误
  if echo "$output" | grep -q "stack too deep"; then
    echo "✗ 发现stack too deep错误: $file"
    echo "$output" | grep -A 5 "stack too deep"
  else
    echo "✓ $file 编译正常"
  fi
  
  echo "---------------------------------"
done

echo "检查完成!"