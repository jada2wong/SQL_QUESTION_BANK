USE [VisionRPT]
GO

DECLARE @StartDate date = '1/1/01'
	,@EndDate date = GETDATE()
	,@Months int = 0 -- all loans 0
	,@Period int = 12 -- all loans 0, monthly 12, weekly 48
	,@Term int = 0 -- all loans 0
	,@Bad varchar(25) = 'Past Due - 120'
		--Past Due - 1
		--'Past Due - 90'
		--Past Due - 60
		--Past Due - 90
		--Past Due - 120

;WITH bad AS (
	SELECT *
	FROM (
		SELECT x.ApplicationNum
			,x.PaymentDate ChargeOffDate
			,x.EndBalanceStatic ChargeOffAmount
			,ROW_NUMBER() OVER (PARTITION BY x.ApplicationNum ORDER BY x.PaymentDate ASC) RowNum
		FROM Allegiant.dbo.tPaymentHistory x
		WHERE (x.StreamPeriod = @Period OR @Period = 0)
			AND (x.StreamTerm = @Term OR @Term = 0)
			--AND x.StreamNum = 1
			AND x.DelinquencyStatus = @Bad
		) z
	WHERE RowNum = 1
	)
	, Organic AS (
		SELECT GuarantorID
			,COUNT(GuarantorID) Count
		FROM Allegiant.dbo.tGuarantorLoan
		GROUP BY GuarantorID
	)

SELECT l.ApplicationNum
	,l.FirstPaymentDate
	--,DATEDIFF(MM,l.FirstPaymentDate,GETDATE())+1 Bucket
	,YEAR(l.FirstPaymentDate) Year
	--,DATEPART(q,FirstPaymentDate) Bucket
	,YEAR(l.FirstPaymentDate) Bucket
	--,YEAR(FirstPaymentDate)*10 + CASE WHEN Month(FirstPaymentDate) < 7 THEN 1 ELSE 2 END Bucket
	--,CASE WHEN o.GuarantorID IS NOT NULL THEN 1 ELSE 0 END Bucket
	--,si.SubRegion AS Bucket
	--,CASE WHEN g8.PrimIncSource IN (1,3) THEN 1 ELSE 0 END Bucket
	,CASE WHEN a8.CMSFairIsaacScore >= 750 THEN 750
		WHEN a8.CMSFairIsaacScore >= 700 THEN 700
		WHEN a8.CMSFairIsaacScore >= 650 THEN 650
		WHEN a8.CMSFairIsaacScore >= 600 THEN 600
		ELSE 0
		END FICOBucket
	--,CASE WHEN nc.NewCMS >= 750 THEN 750
	--	WHEN nc.NewCMS >= 700 THEN 700
	--	WHEN nc.NewCMS >= 650 THEN 650
	--	WHEN nc.NewCMS >= 600 THEN 600
	--	ELSE 0
	--	END Bucket

	,Program = 
         CASE WHEN z.Product in ('New Logic','OnDeck','AMI','KATALYST','TPF') THEN 'Other(TPF)'
			 WHEN z.MedicalTitle in ('CPA','FA','IA','ENGR','ARCH','ATY') THEN 'BHG Pro'
			 WHEN z.GroupX = 1 THEN 'GroupX'
			 WHEN z.FExloan=1 THEN 'Fund-Ex'
			 WHEN z.LoanType = 'Consumer' THEN 'Consumer'
				ELSE 'Core Commercial' END 

	,Riskgrade =  CASE WHEN nc.NewCMS<635 THEN 'F'
		 WHEN NewCMS<685 THEN 'E'
		 WHEN NewCMS<710 THEN 'D'
		 WHEN NewCMS<760 THEN 'C'
		 WHEN NewCMS<835 THEN 'B'
		 WHEN NewCMS>=835 THEN 'A'
		ELSE 'n/a' 
		END 
	,ProductBucket = CASE WHEN l.LoanType = 'CON' THEN 'Consumer' ELSE 'Commercial' END 
	,a8.CMSFairIsaacScore
	,nc.NewCMS
	,l.TotalFinanceAmount
	,l.Term	
	,1 Count
	,CASE WHEN c.ChargeOffDate <= DATEADD(MM,@Months,l.FirstPaymentDate) OR @Months = 0
			THEN 1
			ELSE 0
			END DefaultCount
	,CASE WHEN c.ChargeOffDate <= DATEADD(MM,@Months,l.FirstPaymentDate) OR @Months = 0
			THEN c.ChargeOffDate
			ELSE null
			END ChargeOffDate
	,CASE WHEN c.ChargeOffDate <= DATEADD(MM,@Months,l.FirstPaymentDate) OR @Months = 0
			THEN
				CASE WHEN ChargeOffAmount > l.TotalFinanceAmount
				THEN l.TotalFinanceAmount
				ELSE ChargeOffAmount
				END
			ELSE null
			END ChargeOffAmount
	,DATEDIFF(MM,l.FirstPaymentDate,GETDATE())+1 Months
	,DATEDIFF(MM,l.FirstPaymentDate,GETDATE())+1 FundMonths
	,DATEDIFF(MM,l.FirstPaymentDate,c.ChargeOffDate)+1 ChargeOffMonths
INTO #Loans
FROM Allegiant.dbo.tLoans l
	LEFT JOIN bad c ON c.ApplicationNum = l.ApplicationNum
	LEFT JOIN Vision.sub8900.tApplication8900 a8 ON a8.ApplicationNum = l.ApplicationNum
	LEFT JOIN Vision.sub8900.tGuarantor8900 g8 ON g8.ApplicationNum = l.ApplicationNum AND g8.GuarantorNum = 1
	LEFT JOIN Allegiant.dbo.tGuarantorLoan gl ON gl.LoanID = l.ApplicationNum AND gl.GuarantorNum = 1
	LEFT JOIN Allegiant.dbo.tGuarantor gg ON gg.GuarantorID = gl.GuarantorID
	LEFT JOIN Allegiant.dbo.tStateInfo si ON si.StateCode = gg.State
	LEFT JOIN Organic o ON o.GuarantorID = gl.GuarantorID AND o.Count > 1
	LEFT JOIN VisionRPT.syr.tNewCMS nc ON nc.ApplicationNum = l.ApplicationNum
	LEFT JOIN leadstaging.dbo.approvaltoclosingdata_view z ON z.ApplicationNum = l.ApplicationNum
WHERE l.FirstPaymentDate BETWEEN @StartDate AND @EndDate
	AND (DATEDIFF(MM,l.FirstPaymentDate,GETDATE()) >= @Months OR @Months = 0)
	AND (l.Term = @Term OR @Term = 0)
	AND (l.Period = @Period OR @Period = 0)
	AND a8.CMSFairIsaacScore IS NOT NULL
	--AND nc.NewCMS IS NOT NULL
ORDER BY l.FirstPaymentDate

SELECT * FROM #Loans

;WITH months AS (
	SELECT 1 Months
	UNION ALL
	SELECT Months + 1
	FROM months
	WHERE Months < 84)

SELECT DISTINCT l.Bucket
	,l.Year
	,m.Months
	,CAST(NULL as decimal(20,2)) TotalFinanceAmount
	,CAST(NULL as decimal(20,2)) ChargeOffAmount
	,CAST(NULL as decimal(20,0)) LoanCount
	,CAST(NULL as decimal(20,0)) DefaultCount
INTO #Temp
FROM months m
	OUTER APPLY #Loans l 
WHERE l.FundMonths > m.Months
	AND (m.Months <= @Months OR @Months = 0)
	AND l.Bucket IS NOT NULL
ORDER BY l.Bucket
	,m.Months

UPDATE #Temp
	SET TotalFinanceAmount =
		(SELECT SUM(l.TotalFinanceAmount)
			FROM #Loans l
			WHERE l.Bucket = #Temp.Bucket
					AND YEAR(l.FirstPaymentDate) = #Temp.Year)

UPDATE #Temp
	SET ChargeOffAmount =
		COALESCE((SELECT SUM(l.ChargeOffAmount)
				FROM #Loans l
				WHERE l.Bucket = #Temp.Bucket
					AND YEAR(l.FirstPaymentDate) = #Temp.Year
					AND l.ChargeOffMonths <= #Temp.Months
					AND l.DefaultCount = 1),0)

UPDATE #Temp
	SET LoanCount =
		(SELECT COUNT(l.TotalFinanceAmount)
			FROM #Loans l
			WHERE l.Bucket = #Temp.Bucket
				AND YEAR(l.FirstPaymentDate) = #Temp.Year)

UPDATE #Temp
	SET DefaultCount =
		COALESCE((SELECT COUNT(l.ChargeOffAmount)
				FROM #Loans l
				WHERE l.Bucket = #Temp.Bucket
					AND YEAR(l.FirstPaymentDate) = #Temp.Year
					AND l.ChargeOffMonths <= #Temp.Months
					AND l.DefaultCount = 1),0)

	SELECT * FROM #Temp order by Bucket, Year

--SELECT *
--FROM #Loans
--ORDER BY FirstPaymentDate

--SELECT Bucket
--	,SUM(TotalFinanceAmount) TotalFinanceAmount
--	,COALESCE(SUM(ChargeOffAmount),0) ChargeOffAmount
--	,CAST(CAST(COALESCE(SUM(ChargeOffAmount),0) as decimal(20,4))/CAST(SUM(TotalFinanceAmount) as decimal(20,4)) as decimal(20,4)) ChargeOffRatio
--	,COUNT(TotalFinanceAmount) LoanCount
--	,COUNT(ChargeOffAmount) DefaultCount
--	,CAST(CAST(COUNT(ChargeOffAmount) as decimal(20,4))/CAST(COUNT(TotalFinanceAmount) as decimal(20,4)) as decimal(20,4)) DefaultRatio
--FROM #Loans
--GROUP BY Bucket
--ORDER BY Bucket

SELECT Bucket
	,Year
	,Months
	,TotalFinanceAmount
	,ChargeOffAmount
	,CAST(ChargeOffAmount/TotalFinanceAmount as decimal(20,4)) ChargeOffRatio
	,LoanCount
	,DefaultCount
	,CAST(DefaultCount/LoanCount as decimal(20,4)) DefaultRatio
INTO #Temp2
FROM #Temp
ORDER BY Bucket
	,Months



--SELECT a.*
--	,COALESCE(a.DefaultRatio - b.DefaultRatio,0.0000) Change
--	,ROW_NUMBER() OVER (PARTITION BY a.year ORDER BY a.Year DESC,a.ChargeOffRatio DESC) RowNum
--INTO #TempTailRemoved
--FROM #Temp2 a
--	LEFT JOIN #Temp2 b ON b.Bucket = a.Bucket AND b.Months = a.Months - 1
--ORDER BY a.Bucket
--	,a.Months

SELECT a.Bucket
	,a.Year
	,a.Months
	,SUM(a.ChargeOffRatio) ChargeOffRatio
INTO #Temp3
FROM #Temp2 a
GROUP BY a.Bucket,a.Months, a.Year



SELECT * 
	,ROW_NUMBER() OVER (PARTITION BY Bucket ORDER BY ChargeOffRatio DESC, Months DESC) RowNum
INTO #Temp4
FROM #Temp3

SELECT *
INTO #MaxChargeOffPerYear
FROM #Temp4
WHERE RowNum = 1

SELECT DISTINCT t.*
FROM #Temp3 t
	JOIN #MaxChargeOffPerYear m ON m.Bucket = t.Bucket 
WHERE t.Months <= m.Months
ORDER BY t.Year

DROP TABLE #Temp
DROP TABLE #Temp2
DROP TABLE #Temp3
DROP TABLE #Temp4
DROP TABLE #Loans
DROP TABLE #MaxChargeOffPerYear
